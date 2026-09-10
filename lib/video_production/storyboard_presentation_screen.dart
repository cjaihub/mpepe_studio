import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/project_repository.dart';
import 'pdf_export_service.dart';

class StoryboardPresentationScreen extends ConsumerStatefulWidget {
  final StudioProject project;
  const StoryboardPresentationScreen({super.key, required this.project});

  @override
  ConsumerState<StoryboardPresentationScreen> createState() => _StoryboardPresentationScreenState();
}

class _StoryboardPresentationScreenState extends ConsumerState<StoryboardPresentationScreen> {
  final PageController _pageController = PageController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  bool _isListening = false;
  bool _speechEnabled = false;
  int _currentIndex = 0;
  
  bool _isGridView = false;
  late List<String> _currentUrls;
  
  // Slideshow
  Timer? _slideshowTimer;
  bool _isPlaying = false;
  
  // Signature settings
  Color _penColor = Colors.orangeAccent;
  double _penStrokeWidth = 4.0;
  
  late List<SignatureController> _signatureControllers;
  
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _currentUrls = List.from(widget.project.storyboardUrls);
    _initSignatures();
    _initSpeech();
  }
  
  void _initSignatures() {
    _signatureControllers = List.generate(
      _currentUrls.length,
      (index) => SignatureController(
        penStrokeWidth: _penStrokeWidth, 
        penColor: _penColor, 
        exportBackgroundColor: Colors.transparent,
      ),
    );
  }

  void _initSpeech() async {
    _speechEnabled = await _speech.initialize(
      onStatus: (status) => debugPrint('STT Status: $status'),
      onError: (error) => debugPrint('STT Error: $error'),
    );
    if (mounted) setState(() {});
  }
  
  void _updatePenSettings(Color color, double width) {
    setState(() {
      _penColor = color;
      _penStrokeWidth = width;
    });
    for (int i = 0; i < _signatureControllers.length; i++) {
      final oldController = _signatureControllers[i];
      final points = oldController.points;
      
      final newController = SignatureController(
        points: points,
        penColor: color,
        penStrokeWidth: width,
        exportBackgroundColor: Colors.transparent,
      );
      
      _signatureControllers[i] = newController;
      oldController.dispose();
    }
  }

  void _startListening() async {
    if (!_speechEnabled) return;
    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        debugPrint('Recognized: $words');
        if (words.contains('next')) {
          _nextSlide();
          _stopListening();
        } else if (words.contains('back') || words.contains('previous')) {
          _prevSlide();
          _stopListening();
        } else if (words.contains('clear')) {
          _signatureControllers[_currentIndex].clear();
          _stopListening();
        } else if (words.contains('play')) {
          _toggleSlideshow();
          _stopListening();
        }
      },
    );
    setState(() => _isListening = true);
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  void _nextSlide() {
    if (_currentIndex < _currentUrls.length - 1) {
      _pageController.nextPage(duration: 400.ms, curve: Curves.easeInOut);
    } else if (_isPlaying) {
      _toggleSlideshow(); // Stop when reaching the end
    }
  }

  void _prevSlide() {
    if (_currentIndex > 0) {
      _pageController.previousPage(duration: 400.ms, curve: Curves.easeInOut);
    }
  }
  
  void _toggleSlideshow() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _slideshowTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
          _nextSlide();
        });
      } else {
        _slideshowTimer?.cancel();
        _slideshowTimer = null;
      }
    });
  }

  Future<void> _sharePdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final file = await PdfExportService.generateStoryboardPdf(
        project: widget.project,
        storyboardUrls: _currentUrls,
        signatureControllers: _signatureControllers,
      );
      if (file != null) {
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: '${widget.project.title} - Storyboard Presentation'));
      }
    } catch (e) {
      debugPrint('Share Error: $e');
    }
    setState(() => _isGeneratingPdf = false);
  }
  
  Future<void> _saveReorderedProject() async {
    try {
      final repo = ref.read(projectRepositoryProvider);
      final updatedProject = widget.project.copyWith(storyboardUrls: _currentUrls);
      await repo.addProject(updatedProject);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order saved to project.')));
      }
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _slideshowTimer?.cancel();
    for (var controller in _signatureControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUrls.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Storyboard'), backgroundColor: Colors.black),
        body: const Center(child: Text('No storyboard visuals available.', style: TextStyle(color: Colors.white70))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isGridView ? _buildGridView() : _buildPresentationView(),
    );
  }
  
  Widget _buildGridView() {
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('Drag and drop to reorder shots. Changes auto-save.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ReorderableGridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 16 / 9,
                ),
                itemCount: _currentUrls.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final element = _currentUrls.removeAt(oldIndex);
                    _currentUrls.insert(newIndex, element);
                    
                    // Reorder signature controllers to match
                    final sig = _signatureControllers.removeAt(oldIndex);
                    _signatureControllers.insert(newIndex, sig);
                  });
                  _saveReorderedProject();
                },
                itemBuilder: (context, index) {
                  return Card(
                    key: ValueKey(_currentUrls[index]),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(_currentUrls[index], fit: BoxFit.cover),
                        Container(color: Colors.black26),
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                            child: Text('Shot ${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _currentIndex = index;
                                  _isGridView = false;
                                });
                                // wait for view to switch before animating
                                Future.delayed(50.ms, () {
                                  if (_pageController.hasClients) {
                                    _pageController.jumpToPage(index);
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresentationView() {
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          onPageChanged: (idx) => setState(() => _currentIndex = idx),
          itemCount: _currentUrls.length,
          itemBuilder: (context, index) {
            return Stack(
              fit: StackFit.expand,
              children: [
                // AI Background Image
                Image.network(
                  _currentUrls[index],
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.orange));
                  },
                  errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.white24)),
                ),
                
                // Gradient Overlay for text readability
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent, Colors.black87],
                    ),
                  ),
                ),

                // Signature Drawing Area
                Signature(
                  controller: _signatureControllers[index],
                  backgroundColor: Colors.transparent,
                ),
              ],
            );
          },
        ),
        
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHeader(),
              _buildToolbarAndDetails(),
            ],
          ),
        ),
        
        // Next/Prev Overlay Areas
        Positioned(
          left: 0,
          top: MediaQuery.of(context).size.height / 3,
          bottom: MediaQuery.of(context).size.height / 3,
          width: 80,
          child: GestureDetector(
            onTap: _prevSlide,
            behavior: HitTestBehavior.translucent,
            child: const Align(alignment: Alignment.centerLeft, child: Icon(Icons.chevron_left, color: Colors.white38, size: 64)),
          ),
        ),
        Positioned(
          right: 0,
          top: MediaQuery.of(context).size.height / 3,
          bottom: MediaQuery.of(context).size.height / 3,
          width: 80,
          child: GestureDetector(
            onTap: _nextSlide,
            behavior: HitTestBehavior.translucent,
            child: const Align(alignment: Alignment.centerRight, child: Icon(Icons.chevron_right, color: Colors.white38, size: 64)),
          ),
        ),
        
        if (_isGeneratingPdf)
          Container(
            color: Colors.black87,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.orange),
                  SizedBox(height: 16),
                  Text('Generating PDF...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          )
      ],
    );
  }
  
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
          
          if (!_isGridView)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Text('Shot ${_currentIndex + 1} of ${_currentUrls.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          else
            const Text('Storyboard Grid', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            
          Row(
            children: [
              IconButton(
                icon: Icon(_isGridView ? Icons.slideshow : Icons.grid_view, color: Colors.white, size: 28),
                onPressed: () {
                  setState(() {
                    _isGridView = !_isGridView;
                  });
                  if (!_isGridView) {
                    Future.delayed(50.ms, () {
                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(_currentIndex);
                      }
                    });
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 28),
                onPressed: _sharePdf,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildToolbarAndDetails() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Floating Drawing Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    _buildColorBtn(Colors.orangeAccent),
                    _buildColorBtn(Colors.redAccent),
                    _buildColorBtn(Colors.white),
                    _buildColorBtn(Colors.transparent, isEraser: true),
                    Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                    IconButton(
                      icon: const Icon(Icons.undo, color: Colors.white70, size: 20),
                      onPressed: () => _signatureControllers[_currentIndex].undo(),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 20),
                      onPressed: () => _signatureControllers[_currentIndex].clear(),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Bottom Glassmorphism Details Panel
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.project.title,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.orange, size: 32),
                          onPressed: _toggleSlideshow,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 16),
                        if (_speechEnabled) 
                          GestureDetector(
                            onTap: _isListening ? _stopListening : _startListening,
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: _isListening ? Colors.redAccent : Colors.white54,
                              size: 28,
                            ).animate(target: _isListening ? 1 : 0).scaleXY(end: 1.2, duration: 300.ms),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Draw directly on the screen to add notes.',
                  style: TextStyle(color: Colors.orangeAccent.withValues(alpha: 0.8), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildColorBtn(Color color, {bool isEraser = false}) {
    final isSelected = isEraser ? _penColor == Colors.transparent : _penColor == color;
    return GestureDetector(
      onTap: () {
        if (isEraser) {
          _updatePenSettings(Colors.transparent, 20.0);
        } else {
          _updatePenSettings(color, 4.0);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isEraser ? Colors.grey : color,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 2),
        ),
        child: isEraser ? const Icon(Icons.edit_off, size: 14, color: Colors.white) : null,
      ),
    );
  }
}
