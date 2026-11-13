package com.oneova.camerakit.ar

import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Filament
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.SwapChain
import com.google.android.filament.Texture
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.FilamentInstance
import com.google.android.filament.gltfio.Gltfio
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/** A 3D effect: a glTF model worn at an anchor of each tracked face. */
internal class Ar3dSpec(
    val id: String,
    val anchor: String,
    val scale: Float,
    val offsetX: Float,
    val offsetY: Float,
    /** Metres toward the camera, after the anchor placement. */
    val offsetZ: Float,
    /** Model alignment in degrees (applied to the model before placement). */
    val rotX: Float,
    val rotY: Float,
    val rotZ: Float,
)

/**
 * Physically based 3D effects on faces (Filament + gltfio), drawn into a
 * transparent layer the camera pipeline composites over the preview, the
 * recording and stills.
 *
 * - Models are glTF 2.0 binaries downloaded by the app and handed over with
 *   [putModel]; each is instanced for up to [MAX_FACES] people.
 * - Pose comes from the face mesh (eyes centre, face width → distance, yaw /
 *   pitch / roll → orientation) through a pinhole camera with the phone's
 *   field of view, so the model sits on the head in perspective.
 * - A head-shaped occluder per face writes depth only, so the parts of a
 *   model behind the head (glasses arms, the back of a hat) are hidden.
 * - Lighting follows the scene: a sky/ground environment and a key light
 *   whose strength and colour come from the camera frame's brightness and
 *   average colour.
 *
 * Filament's engine is process-wide and lives on one thread ([thread]); a
 * renderer object per camera session owns the view and its swap chain.
 */
internal class Ar3dRenderer(private val surface: Surface, private var width: Int, private var height: Int) {

    /** One frame to draw: tracked faces in normalized preview space. */
    class Frame(val faces: List<ArFace>, val light: Float, val tint: FloatArray?, val width: Int, val height: Int)

    private class Model(val asset: FilamentAsset, val instances: Array<FilamentInstance>, val center: FloatArray, val half: FloatArray)

    private val pending = AtomicReference<Frame?>(null)
    private val specs = AtomicReference<List<Ar3dSpec>>(emptyList())
    private var swapChain: SwapChain? = null
    private var view: View? = null
    private var scene: Scene? = null
    private var camera: Camera? = null
    private var cameraEntity = 0
    private var sun = 0
    private var indirect: IndirectLight? = null
    private var envTex: Texture? = null
    private var occluder: Model? = null
    private val models = HashMap<String, Model>()
    private val shown = HashSet<Int>()
    private var lastTintKey = -1
    @Volatile private var released = false

    /** Called with true when the layer has content, false when it went empty. */
    @Volatile var onContent: ((Boolean) -> Unit)? = null
    private var hadContent = false

    init {
        post { setUp() }
    }

    val active: Boolean get() = specs.get().isNotEmpty()

    fun setSpecs(next: List<Ar3dSpec>) {
        specs.set(next)
        if (next.isEmpty()) post { draw(Frame(emptyList(), 0.5f, null, width, height)) }
    }

    /** Loads (or replaces) model [id] from a .glb file on disk. */
    fun putModel(id: String, path: String, done: (String?) -> Unit) = post {
        val err = runCatching { load(id, File(path)) }.exceptionOrNull()
        if (err != null) Log.w(TAG, "Could not load 3D model $id", err)
        done(err?.message)
    }

    fun retainModels(ids: Set<String>) = post {
        for (id in models.keys - ids) models.remove(id)?.let(::destroyModel)
    }

    /** Requests a render; frames that arrive while one is drawing replace each other. */
    fun request(frame: Frame) {
        if (released || pending.getAndSet(frame) != null) return
        post { pending.getAndSet(null)?.let(::draw) }
    }

    fun release() {
        released = true
        post {
            runCatching {
                val e = engine ?: return@runCatching
                for (m in models.values) destroyModel(m)
                models.clear()
                occluder?.let(::destroyModel)
                occluder = null
                scene?.let { s ->
                    if (sun != 0) s.removeEntity(sun)
                }
                if (sun != 0) {
                    e.destroyEntity(sun)
                    EntityManager.get().destroy(sun)
                }
                indirect?.let(e::destroyIndirectLight)
                envTex?.let(e::destroyTexture)
                view?.let(e::destroyView)
                scene?.let(e::destroyScene)
                if (cameraEntity != 0) {
                    e.destroyCameraComponent(cameraEntity)
                    EntityManager.get().destroy(cameraEntity)
                }
                swapChain?.let(e::destroySwapChain)
                e.flushAndWait()
            }.onFailure { Log.w(TAG, "3D release failed", it) }
            swapChain = null
        }
    }

    /** Blocks until the 3D thread has finished the work posted so far (max 500 ms). */
    fun awaitIdle() {
        val l = java.util.concurrent.CountDownLatch(1)
        handler.post { l.countDown() }
        l.await(500, java.util.concurrent.TimeUnit.MILLISECONDS)
    }

    // ── Set-up ─────────────────────────────────────────────────────────────

    private fun setUp() {
        val e = engine() ?: return
        swapChain = e.createSwapChain(surface, com.google.android.filament.SwapChainFlags.CONFIG_TRANSPARENT)
        val s = e.createScene()
        cameraEntity = EntityManager.get().create()
        val cam = e.createCamera(cameraEntity)
        // Exposure 1: light intensities below are in display units, so the
        // model's brightness matches the camera picture it sits in.
        cam.setExposure(1f)
        val v = e.createView().apply {
            scene = s
            camera = cam
            blendMode = View.BlendMode.TRANSLUCENT
            viewport = Viewport(0, 0, width, height)
            // Soft, physically plausible look without post effects that would
            // touch the camera picture around the model.
            setShadowingEnabled(false)
            ambientOcclusionOptions = ambientOcclusionOptions.apply { enabled = false }
            bloomOptions = bloomOptions.apply { enabled = false }
        }
        sun = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.SUN)
            .color(1f, 0.98f, 0.95f)
            .intensity(2.4f)
            .direction(0.35f, -0.8f, -0.5f)
            .sunAngularRadius(2.5f)
            .castShadows(false)
            .build(e, sun)
        s.addEntity(sun)
        scene = s
        camera = cam
        view = v
        updateEnvironment(0.5f, null)
        occluder = runCatching { createModel(headOccluderGlb()) }
            .onFailure { Log.w(TAG, "Head occluder failed", it) }
            .getOrNull()
            ?.also { m ->
                val rm = e.renderableManager
                for (inst in m.instances) {
                    for (ent in inst.entities) {
                        if (!rm.hasComponent(ent)) continue
                        val ri = rm.getInstance(ent)
                        // Depth only, drawn first: hides what is behind the head.
                        rm.setPriority(ri, 0)
                        for (p in 0 until rm.getPrimitiveCount(ri)) {
                            rm.getMaterialInstanceAt(ri, p).apply {
                                setColorWrite(false)
                                setDepthWrite(true)
                            }
                        }
                    }
                }
            }
    }

    private fun load(id: String, file: File) {
        val e = engine() ?: throw IllegalStateException("3D engine unavailable")
        val bytes = file.readBytes()
        val buf = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).put(bytes)
        buf.flip()
        val m = createModel(buf)
        models.put(id, m)?.let(::destroyModel)
        val rm = e.renderableManager
        for (inst in m.instances) {
            for (ent in inst.entities) if (rm.hasComponent(ent)) rm.setPriority(rm.getInstance(ent), 4)
        }
    }

    private fun createModel(buf: ByteBuffer): Model {
        val instances = arrayOfNulls<FilamentInstance>(MAX_FACES)
        val asset = assetLoader!!.createInstancedAsset(buf, instances)
            ?: throw IllegalArgumentException("Not a glTF model")
        resourceLoader!!.loadResources(asset)
        asset.releaseSourceData()
        val box = asset.boundingBox
        @Suppress("UNCHECKED_CAST")
        return Model(asset, instances as Array<FilamentInstance>, box.center.copyOf(), box.halfExtent.copyOf())
    }

    private fun destroyModel(m: Model) {
        val s = scene
        for (inst in m.instances) s?.removeEntities(inst.entities)
        shown.removeAll(m.instances.flatMap { it.entities.toList() }.toSet())
        assetLoader?.destroyAsset(m.asset)
    }

    // ── Lighting ───────────────────────────────────────────────────────────

    /**
     * Rebuilds the environment when the scene's brightness or colour changed
     * noticeably: a small prefiltered sky/ground cubemap for reflections and
     * matching spherical-harmonics irradiance for diffuse light.
     */
    private fun updateEnvironment(light: Float, tint: FloatArray?) {
        val e = engine ?: return
        val t = tint ?: floatArrayOf(1f, 1f, 1f)
        val key = (light * 8).toInt() * 1000 + (t[0] * 8).toInt() * 100 + (t[1] * 8).toInt() * 10 + (t[2] * 8).toInt()
        if (key == lastTintKey) return
        lastTintKey = key
        val size = 32
        val levels = 6
        val tex = Texture.Builder()
            .width(size).height(size).levels(levels)
            .sampler(Texture.Sampler.SAMPLER_CUBEMAP)
            .format(Texture.InternalFormat.RGBA8)
            .build(e)
        for (level in 0 until levels) {
            val n = max(1, size shr level)
            val face = n * n * 4
            val data = ByteBuffer.allocateDirect(face * 6).order(ByteOrder.nativeOrder())
            // Rougher levels spread the bright window over more of the sky.
            val spread = 0.12f + level * 0.18f
            for (f in 0 until 6) {
                for (y in 0 until n) for (x in 0 until n) {
                    val u = (x + 0.5f) / n * 2 - 1
                    val v = (y + 0.5f) / n * 2 - 1
                    val d = cubeDir(f, u, v)
                    val c = envColor(d, t, spread)
                    data.put(toByte(c[0])).put(toByte(c[1])).put(toByte(c[2])).put(255.toByte())
                }
            }
            data.flip()
            val offsets = IntArray(6) { it * face }
            tex.setImage(e, level, Texture.PixelBufferDescriptor(data, Texture.Format.RGBA, Texture.Type.UBYTE), offsets)
        }
        // Diffuse: sky above, ground below (2 SH bands, pre-scaled).
        val sky = floatArrayOf(0.9f * t[0], 0.92f * t[1], 0.95f * t[2])
        val ground = floatArrayOf(0.35f * t[0], 0.32f * t[1], 0.3f * t[2])
        val sh = FloatArray(4 * 3)
        for (c in 0 until 3) {
            sh[c] = (sky[c] + ground[c]) * 0.5f
            sh[3 * 2 + c] = (sky[c] - ground[c]) * 0.5f // band 1, y
        }
        val intensity = 0.35f + light * 1.1f
        val ibl = IndirectLight.Builder()
            .reflections(tex)
            .irradiance(2, sh)
            .intensity(intensity)
            .build(e)
        scene?.indirectLight = ibl
        indirect?.let(e::destroyIndirectLight)
        envTex?.let(e::destroyTexture)
        indirect = ibl
        envTex = tex
        if (sun != 0) {
            val lm = e.lightManager
            val li = lm.getInstance(sun)
            lm.setIntensity(li, 0.8f + light * 3.2f)
            lm.setColor(li, 0.6f + 0.4f * t[0], 0.6f + 0.4f * t[1], 0.6f + 0.4f * t[2])
        }
    }

    private fun envColor(d: FloatArray, t: FloatArray, spread: Float): FloatArray {
        val up = d[1]
        val sky = smooth(-0.15f, 0.35f, up)
        val base = 0.18f + 0.62f * sky
        // A soft window up and to the front-left: gives metal and glass a glint.
        val wx = -0.45f; val wy = 0.6f; val wz = 0.66f
        val dot = d[0] * wx + d[1] * wy + d[2] * wz
        val window = exp(((dot - 1f) / spread).toDouble()).toFloat()
        val v = min(1f, base + window * 0.9f)
        return floatArrayOf(v * t[0], v * t[1], v * t[2])
    }

    private fun smooth(a: Float, b: Float, x: Float): Float {
        val k = ((x - a) / (b - a)).coerceIn(0f, 1f)
        return k * k * (3 - 2 * k)
    }

    private fun toByte(v: Float): Byte {
        // Linear → sRGB-ish so the 8-bit sky keeps detail in the darks.
        val s = Math.pow(v.coerceIn(0f, 1f).toDouble(), 1 / 2.2).toFloat()
        return (s * 255f + 0.5f).toInt().coerceIn(0, 255).toByte()
    }

    /** Direction for texel (u, v) of cube face [f] (+X, -X, +Y, -Y, +Z, -Z). */
    private fun cubeDir(f: Int, u: Float, v: Float): FloatArray {
        val d = when (f) {
            0 -> floatArrayOf(1f, -v, -u)
            1 -> floatArrayOf(-1f, -v, u)
            2 -> floatArrayOf(u, 1f, v)
            3 -> floatArrayOf(u, -1f, -v)
            4 -> floatArrayOf(u, -v, 1f)
            else -> floatArrayOf(-u, -v, -1f)
        }
        val l = sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
        return floatArrayOf(d[0] / l, d[1] / l, d[2] / l)
    }

    // ── Drawing ────────────────────────────────────────────────────────────

    private fun draw(frame: Frame) {
        if (released) return
        val e = engine ?: return
        val sc = swapChain ?: return
        val v = view ?: return
        val s = scene ?: return
        val cam = camera ?: return
        if (frame.width > 0 && frame.height > 0 && (frame.width != width || frame.height != height)) {
            width = frame.width
            height = frame.height
            v.viewport = Viewport(0, 0, width, height)
        }
        val list = specs.get()
        val faces = if (list.isEmpty()) emptyList() else frame.faces.take(MAX_FACES)
        updateEnvironment(frame.light, frame.tint)
        val aspect = width.toDouble() / max(1, height)
        cam.setProjection(FOV_V, aspect, 0.02, 10.0, Camera.Fov.VERTICAL)
        cam.lookAt(0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0)

        val want = HashSet<Int>()
        val tm = e.transformManager
        val f = (height / 2.0) / tan(Math.toRadians(FOV_V / 2))
        faces.forEachIndexed { i, face ->
            val head = headMatrix(face, f) ?: return@forEachIndexed
            occluder?.let { o ->
                val inst = o.instances[i]
                tm.setTransform(tm.getInstance(inst.root), head)
                want.addAll(inst.entities.toList())
            }
            for (spec in list) {
                val m = models[spec.id] ?: continue
                val inst = m.instances[i]
                tm.setTransform(tm.getInstance(inst.root), multiply(head, place(spec, m)))
                want.addAll(inst.entities.toList())
            }
        }
        // Show and hide whole instances only when the set changes.
        val add = want - shown
        val remove = shown - want
        if (remove.isNotEmpty()) s.removeEntities(remove.toIntArray())
        if (add.isNotEmpty()) s.addEntities(add.toIntArray())
        shown.clear()
        shown.addAll(want)

        val has = want.isNotEmpty() && models.isNotEmpty() && list.isNotEmpty()
        val r = renderer ?: return
        if (r.beginFrame(sc, System.nanoTime())) {
            r.render(v)
            r.endFrame()
        }
        if (has != hadContent) {
            hadContent = has
            onContent?.invoke(has)
        }
    }

    /**
     * Head pose → model matrix (column-major, metres, camera looking down -Z).
     * Origin between the eyes; +X toward the image-right cheek, +Y up the face,
     * +Z out of the face toward the camera.
     */
    private fun headMatrix(face: ArFace, f: Double): FloatArray? {
        val w = width.toFloat()
        val h = height.toFloat()
        val ex = face.eyesCenter.x * w
        val ey = face.eyesCenter.y * h
        val dx = (face.rightCheek.x - face.leftCheek.x) * w
        val dy = (face.rightCheek.y - face.leftCheek.y) * h
        val widthPx = sqrt(dx * dx + dy * dy)
        if (widthPx < 8f) return null
        // The tracker's angles mix normalized x and y; correct for the aspect.
        val roll = atan2(sin(face.roll) * h, cos(face.roll) * w)
        val yaw = face.yaw
        val pitch = atan2(sin(face.pitch) * w, cos(face.pitch) * h)
        val visible = max(0.45f, cos(yaw))
        val depth = f * HEAD_WIDTH_M / (widthPx / visible)
        val tx = (ex - w / 2) / f * depth
        val ty = -(ey - h / 2) / f * depth
        val tz = -depth

        // Axes in camera space (y up, z toward the viewer).
        val right = norm(floatArrayOf(cos(roll) * cos(yaw), -sin(roll) * cos(yaw), -sin(yaw)))
        val up0 = floatArrayOf(sin(roll) * cos(pitch), cos(roll) * cos(pitch), sin(pitch))
        val fwd = norm(cross(right, up0))
        val up = cross(fwd, right)
        return floatArrayOf(
            right[0], right[1], right[2], 0f,
            up[0], up[1], up[2], 0f,
            fwd[0], fwd[1], fwd[2], 0f,
            tx.toFloat(), ty.toFloat(), tz.toFloat(), 1f,
        )
    }

    /** Model placement on the head for its anchor (head frame, metres). */
    private fun place(spec: Ar3dSpec, m: Model): FloatArray {
        val (aw, ax, ay, az, fit) = when (spec.anchor) {
            "eyes" -> Anchor(0.15f, 0f, 0f, 0.022f, FIT_FRONT)
            "forehead" -> Anchor(0.12f, 0f, 0.055f, 0.0f, FIT_CENTER)
            "headTop", "hair" -> Anchor(0.2f, 0f, 0.06f, -0.075f, FIT_BOTTOM)
            "nose" -> Anchor(0.06f, 0f, -0.035f, 0.03f, FIT_CENTER)
            "mouth" -> Anchor(0.07f, 0f, -0.072f, 0.018f, FIT_CENTER)
            "chin" -> Anchor(0.12f, 0f, -0.115f, -0.005f, FIT_TOP)
            "neck" -> Anchor(0.16f, 0f, -0.15f, -0.06f, FIT_TOP)
            else -> Anchor(0.17f, 0f, -0.02f, -0.02f, FIT_CENTER)
        }
        val extent = max(1e-4f, m.half[0] * 2)
        val k = aw * spec.scale / extent
        // Model alignment first (around its own centre), then fit and place.
        val rot = rotation(spec.rotX, spec.rotY, spec.rotZ)
        val c = m.center
        val rc = apply(rot, c)
        val rh = absApply(rot, m.half)
        val oy = when (fit) {
            FIT_BOTTOM -> -(rc[1] - rh[1])
            FIT_TOP -> -(rc[1] + rh[1])
            else -> -rc[1]
        }
        val oz = if (fit == FIT_FRONT) -(rc[2] + rh[2]) else -rc[2]
        val px = ax + spec.offsetX * HEAD_WIDTH_M + -rc[0] * k
        val py = ay - spec.offsetY * HEAD_WIDTH_M + oy * k
        val pz = az + spec.offsetZ + oz * k
        return floatArrayOf(
            rot[0] * k, rot[1] * k, rot[2] * k, 0f,
            rot[3] * k, rot[4] * k, rot[5] * k, 0f,
            rot[6] * k, rot[7] * k, rot[8] * k, 0f,
            px, py, pz, 1f,
        )
    }

    private data class Anchor(val width: Float, val x: Float, val y: Float, val z: Float, val fit: Int)

    private fun post(r: () -> Unit) {
        handler.post {
            try {
                r()
            } catch (e: Throwable) {
                Log.w(TAG, "3D task failed", e)
            }
        }
    }

    companion object {
        private const val TAG = "OneovaAr3d"
        const val MAX_FACES = 3
        private const val FOV_V = 62.0
        private const val HEAD_WIDTH_M = 0.145f
        private const val FIT_CENTER = 0
        private const val FIT_FRONT = 1
        private const val FIT_BOTTOM = 2
        private const val FIT_TOP = 3

        // Process-wide: Filament's engine and loaders live on one thread for
        // the life of the app (cheap when idle; creating them is not).
        private val thread by lazy { HandlerThread("OneovaAr3d").apply { start() } }
        private val handler by lazy { Handler(thread.looper) }
        private var engine: Engine? = null
        private var renderer: Renderer? = null
        private var assetLoader: AssetLoader? = null
        private var resourceLoader: ResourceLoader? = null
        private var failed = false

        private fun engine(): Engine? {
            if (engine != null || failed) return engine
            return runCatching {
                Filament.init()
                Gltfio.init()
                val e = Engine.create()
                renderer = e.createRenderer().apply {
                    clearOptions = clearOptions.apply {
                        clear = true
                        clearColor = floatArrayOf(0f, 0f, 0f, 0f)
                    }
                }
                assetLoader = AssetLoader(e, UbershaderProvider(e), EntityManager.get())
                resourceLoader = ResourceLoader(e)
                engine = e
                e
            }.onFailure {
                failed = true
                Log.e(TAG, "Filament unavailable", it)
            }.getOrNull()
        }

        private fun norm(v: FloatArray): FloatArray {
            val l = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).coerceAtLeast(1e-6f)
            return floatArrayOf(v[0] / l, v[1] / l, v[2] / l)
        }

        private fun cross(a: FloatArray, b: FloatArray) = floatArrayOf(
            a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0],
        )

        /** Column-major 4×4 product a·b. */
        private fun multiply(a: FloatArray, b: FloatArray): FloatArray {
            val r = FloatArray(16)
            for (c in 0 until 4) for (row in 0 until 4) {
                var s = 0f
                for (k in 0 until 4) s += a[k * 4 + row] * b[c * 4 + k]
                r[c * 4 + row] = s
            }
            return r
        }

        /** Column-major 3×3 rotation from X, then Y, then Z degrees. */
        private fun rotation(xd: Float, yd: Float, zd: Float): FloatArray {
            val x = Math.toRadians(xd.toDouble()); val y = Math.toRadians(yd.toDouble()); val z = Math.toRadians(zd.toDouble())
            val cx = cos(x).toFloat(); val sx = sin(x).toFloat()
            val cy = cos(y).toFloat(); val sy = sin(y).toFloat()
            val cz = cos(z).toFloat(); val sz = sin(z).toFloat()
            // R = Rz · Ry · Rx (row-major below, transposed on return).
            val m = floatArrayOf(
                cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx,
                sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx,
                -sy, cy * sx, cy * cx,
            )
            return floatArrayOf(m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8])
        }

        private fun apply(r: FloatArray, v: FloatArray) = floatArrayOf(
            r[0] * v[0] + r[3] * v[1] + r[6] * v[2],
            r[1] * v[0] + r[4] * v[1] + r[7] * v[2],
            r[2] * v[0] + r[5] * v[1] + r[8] * v[2],
        )

        private fun absApply(r: FloatArray, v: FloatArray) = floatArrayOf(
            kotlin.math.abs(r[0]) * v[0] + kotlin.math.abs(r[3]) * v[1] + kotlin.math.abs(r[6]) * v[2],
            kotlin.math.abs(r[1]) * v[0] + kotlin.math.abs(r[4]) * v[1] + kotlin.math.abs(r[7]) * v[2],
            kotlin.math.abs(r[2]) * v[0] + kotlin.math.abs(r[5]) * v[1] + kotlin.math.abs(r[8]) * v[2],
        )

        /**
         * A head-sized ellipsoid (metres, head frame: origin between the eyes)
         * as a tiny glTF binary, used as the depth-only occluder.
         */
        private fun headOccluderGlb(): ByteBuffer {
            val rings = 18
            val segs = 24
            val cx = 0f; val cy = -0.005f; val cz = -0.088f
            val rx = 0.071f; val ry = 0.118f; val rz = 0.092f
            val pos = ArrayList<Float>()
            for (i in 0..rings) {
                val th = Math.PI * i / rings
                for (j in 0..segs) {
                    val ph = 2 * Math.PI * j / segs
                    pos += (cx + rx * sin(th) * cos(ph)).toFloat()
                    pos += (cy + ry * cos(th)).toFloat()
                    pos += (cz + rz * sin(th) * sin(ph)).toFloat()
                }
            }
            val idx = ArrayList<Short>()
            for (i in 0 until rings) for (j in 0 until segs) {
                val a = i * (segs + 1) + j
                val b = a + segs + 1
                idx += a.toShort(); idx += b.toShort(); idx += (a + 1).toShort()
                idx += (a + 1).toShort(); idx += b.toShort(); idx += (b + 1).toShort()
            }
            val vCount = pos.size / 3
            val posBytes = pos.size * 4
            val idxBytes = idx.size * 2
            val idxPad = (4 - idxBytes % 4) % 4
            val binLen = posBytes + idxBytes + idxPad
            val json = """{"asset":{"version":"2.0","generator":"Oneova"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0}],""" +
                """"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1,"material":0}]}],""" +
                """"materials":[{"pbrMetallicRoughness":{"baseColorFactor":[0,0,0,1]},"doubleSided":true,"extensions":{"KHR_materials_unlit":{}}}],""" +
                """"extensionsUsed":["KHR_materials_unlit"],""" +
                """"accessors":[{"bufferView":0,"componentType":5126,"count":$vCount,"type":"VEC3",""" +
                """"min":[${cx - rx},${cy - ry},${cz - rz}],"max":[${cx + rx},${cy + ry},${cz + rz}]},""" +
                """{"bufferView":1,"componentType":5123,"count":${idx.size},"type":"SCALAR"}],""" +
                """"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":$posBytes,"target":34962},""" +
                """{"buffer":0,"byteOffset":$posBytes,"byteLength":$idxBytes,"target":34963}],""" +
                """"buffers":[{"byteLength":$binLen}]}"""
            val jsonBytes = json.toByteArray(Charsets.UTF_8)
            val jsonPad = (4 - jsonBytes.size % 4) % 4
            val total = 12 + 8 + jsonBytes.size + jsonPad + 8 + binLen
            val b = ByteBuffer.allocateDirect(total).order(ByteOrder.LITTLE_ENDIAN)
            b.putInt(0x46546C67).putInt(2).putInt(total)
            b.putInt(jsonBytes.size + jsonPad).putInt(0x4E4F534A).put(jsonBytes)
            repeat(jsonPad) { b.put(0x20) }
            b.putInt(binLen).putInt(0x004E4942)
            for (p in pos) b.putFloat(p)
            for (s in idx) b.putShort(s)
            repeat(idxPad) { b.put(0) }
            b.flip()
            return b
        }
    }
}
