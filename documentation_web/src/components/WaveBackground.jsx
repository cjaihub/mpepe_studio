import React, { useEffect, useRef } from 'react';

/**
 * WaveBackground
 * Renders an advanced wired net grid wave mesh in Oneova brand colors (#007AFF & #FF2D87).
 * Features:
 * - Interconnected horizontal and vertical wireframe net grid.
 * - Dynamic 3D undulating wave topology.
 * - Reactive "wake-up" spring impulse that ripples when mouse movement is detected.
 * - Depth-of-field blur spotlight and radiant neon reflections.
 * - Highly optimized with mobile device-pixel scaling and adaptive step resolution.
 */
export default function WaveBackground({ theme = 'dark' }) {
  const canvasRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d', { alpha: true });
    if (!ctx) return;

    let animationFrameId;
    let width = (canvas.width = window.innerWidth);
    let height = (canvas.height = window.innerHeight);

    // Mouse state with smooth lerping & wake-up intensity
    const mouse = {
      x: width / 2,
      y: height / 2,
      targetX: width / 2,
      targetY: height / 2,
      wakeUpIntensity: 0.2, // Base calm energy
      rippleTime: 0,
      isMoving: false,
      lastMoveTime: Date.now()
    };

    const handleResize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = width * dpr;
      canvas.height = height * dpr;
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
    };

    handleResize();
    window.addEventListener('resize', handleResize);

    const handleMouseMove = (e) => {
      mouse.targetX = e.clientX;
      mouse.targetY = e.clientY;
      mouse.isMoving = true;
      mouse.lastMoveTime = Date.now();
      // Wake up the net waves when mouse movement is detected
      mouse.wakeUpIntensity = Math.min(mouse.wakeUpIntensity + 0.12, 1.0);
    };

    const handleTouchMove = (e) => {
      if (e.touches && e.touches[0]) {
        mouse.targetX = e.touches[0].clientX;
        mouse.targetY = e.touches[0].clientY;
        mouse.isMoving = true;
        mouse.lastMoveTime = Date.now();
        mouse.wakeUpIntensity = Math.min(mouse.wakeUpIntensity + 0.15, 1.0);
      }
    };

    window.addEventListener('mousemove', handleMouseMove, { passive: true });
    window.addEventListener('touchmove', handleTouchMove, { passive: true });

    let clock = 0;

    const render = () => {
      // Smoothly track mouse
      mouse.x += (mouse.targetX - mouse.x) * 0.09;
      mouse.y += (mouse.targetY - mouse.y) * 0.09;

      // Decay wake-up intensity back toward calm baseline (0.12) if idle
      if (Date.now() - mouse.lastMoveTime > 150) {
        mouse.isMoving = false;
        mouse.wakeUpIntensity += (0.12 - mouse.wakeUpIntensity) * 0.035;
      }

      clock += 0.016;
      mouse.rippleTime += 0.02 + mouse.wakeUpIntensity * 0.035;

      ctx.clearRect(0, 0, width, height);

      const isDark = theme === 'dark';

      // 1. Mouse Wake-up Radial Ambient Spotlight (Frosted Glow)
      const spotRadius = isDark ? 420 : 360;
      const spotGrad = ctx.createRadialGradient(
        mouse.x,
        mouse.y,
        0,
        mouse.x,
        mouse.y,
        spotRadius
      );
      if (isDark) {
        spotGrad.addColorStop(0, `rgba(0, 122, 255, ${0.22 * (0.6 + mouse.wakeUpIntensity * 0.5)})`);
        spotGrad.addColorStop(0.35, `rgba(255, 45, 135, ${0.14 * (0.6 + mouse.wakeUpIntensity * 0.5)})`);
        spotGrad.addColorStop(1, 'rgba(4, 5, 7, 0)');
      } else {
        spotGrad.addColorStop(0, `rgba(0, 122, 255, ${0.14 * (0.6 + mouse.wakeUpIntensity * 0.5)})`);
        spotGrad.addColorStop(0.35, `rgba(255, 45, 135, ${0.08 * (0.6 + mouse.wakeUpIntensity * 0.5)})`);
        spotGrad.addColorStop(1, 'rgba(248, 250, 252, 0)');
      }
      ctx.fillStyle = spotGrad;
      ctx.fillRect(0, 0, width, height);

      // 2. Wired Net Grid Configuration (Small Grid Cells for dense, high-tech mesh)
      const isMobile = width < 768;
      const cellSize = isMobile ? 32 : 22;
      const cols = Math.ceil(width / cellSize) + 1;
      const rows = Math.ceil(height / cellSize) + 1;

      // 2D Array of points with wave elevation
      const grid = [];
      const mouseRadius = isMobile ? 240 : 360;

      for (let r = 0; r < rows; r++) {
        const rowPoints = [];
        const baseY = r * cellSize;

        for (let c = 0; c < cols; c++) {
          const baseX = c * cellSize;

          // Ambient harmonic wave displacement (Smooth, active breathing wave)
          const wave1 = Math.sin(baseX * 0.0038 + clock * 0.85) * Math.cos(baseY * 0.0038 + clock * 0.65) * 12;
          const wave2 = Math.sin((baseX + baseY) * 0.0028 + clock * 1.15) * 7.5;

          // Interactive mouse wake-up ripple & kinetic impulse
          const distToMouse = Math.hypot(baseX - mouse.x, baseY - mouse.y);
          let mouseDisplacement = 0;
          let nodeGlow = 0;

          if (distToMouse < mouseRadius) {
            const factor = 1 - distToMouse / mouseRadius;
            // Concentric ripple waves propagating outward from cursor
            mouseDisplacement = Math.sin(distToMouse * 0.040 - mouse.rippleTime * 4.6) * (factor * 30 * mouse.wakeUpIntensity);
            nodeGlow = factor * (0.35 + mouse.wakeUpIntensity * 0.75);
          }

          const elevation = wave1 + wave2 + mouseDisplacement;

          rowPoints.push({
            x: baseX,
            y: baseY + elevation,
            glow: nodeGlow
          });
        }
        grid.push(rowPoints);
      }

      // Base line colors depending on theme - Highly active and clearly visible in both themes
      const lineAlphaBase = isDark ? 0.20 : 0.18;
      const blueColor = isDark ? '0, 122, 255' : '0, 102, 230';
      const pinkColor = isDark ? '255, 45, 135' : '235, 25, 115';

      // 3. Draw Horizontal Net Grid Wires with smooth curves
      for (let r = 0; r < rows; r++) {
        ctx.beginPath();
        for (let c = 0; c < cols; c++) {
          const pt = grid[r][c];
          if (c === 0) {
            ctx.moveTo(pt.x, pt.y);
          } else {
            // Smooth curve to next point
            const prev = grid[r][c - 1];
            const midX = (prev.x + pt.x) / 2;
            const midY = (prev.y + pt.y) / 2;
            ctx.quadraticCurveTo(prev.x, prev.y, midX, midY);
            if (c === cols - 1) {
              ctx.lineTo(pt.x, pt.y);
            }
          }
        }
        // Alternate subtle blue and pink gradient tracks
        const isPinkRow = r % 2 === 1;
        const baseColor = isPinkRow ? pinkColor : blueColor;
        ctx.strokeStyle = `rgba(${baseColor}, ${lineAlphaBase + (isPinkRow ? 0.03 : 0.05)})`;
        ctx.lineWidth = 1.1;
        ctx.stroke();
      }

      // 4. Draw Vertical Net Grid Wires (Creates the Interconnected Wired Small Grid Mesh)
      for (let c = 0; c < cols; c++) {
        ctx.beginPath();
        for (let r = 0; r < rows; r++) {
          const pt = grid[r][c];
          if (r === 0) {
            ctx.moveTo(pt.x, pt.y);
          } else {
            const prev = grid[r - 1][c];
            const midX = (prev.x + pt.x) / 2;
            const midY = (prev.y + pt.y) / 2;
            ctx.quadraticCurveTo(prev.x, prev.y, midX, midY);
            if (r === rows - 1) {
              ctx.lineTo(pt.x, pt.y);
            }
          }
        }
        const isBlueCol = c % 2 === 0;
        const baseColor = isBlueCol ? blueColor : pinkColor;
        ctx.strokeStyle = `rgba(${baseColor}, ${lineAlphaBase + (isBlueCol ? 0.02 : 0.01)})`;
        ctx.lineWidth = 1.0;
        ctx.stroke();
      }

      // 5. Draw Active Mouse Wake-Up Wave Highlights & Node Embers
      const nodeStep = isMobile ? 2 : 1;
      for (let r = 0; r < rows; r += nodeStep) {
        for (let c = 0; c < cols; c += nodeStep) {
          const pt = grid[r][c];
          if (pt.glow > 0.08) {
            // Illuminated glowing wire nodes at grid intersections
            ctx.beginPath();
            ctx.arc(pt.x, pt.y, 1.4 + pt.glow * 2.6, 0, Math.PI * 2);
            const isPinkNode = (r + c) % 2 === 0;
            const nodeRgb = isPinkNode ? '255, 45, 135' : '0, 122, 255';
            ctx.fillStyle = `rgba(${nodeRgb}, ${pt.glow * 0.95})`;
            ctx.shadowColor = `rgb(${nodeRgb})`;
            ctx.shadowBlur = isDark ? (12 * pt.glow) : (6 * pt.glow);
            ctx.fill();
            ctx.shadowBlur = 0;
          }
        }
      }

      animationFrameId = requestAnimationFrame(render);
    };

    render();

    return () => {
      window.removeEventListener('resize', handleResize);
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('touchmove', handleTouchMove);
      cancelAnimationFrame(animationFrameId);
    };
  }, [theme]);

  return (
    <div className="wave-net-background-wrap" aria-hidden="true">
      <canvas ref={canvasRef} className="interactive-wave-canvas" />
      {/* Frosted depth-of-field blur overlay for smooth organic aesthetics */}
      <div className="wave-net-blur-vignette" />
    </div>
  );
}
