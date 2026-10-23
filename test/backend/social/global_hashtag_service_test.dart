import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:oneova/backend/social/services/global_hashtag_service.dart';

void main() {
  group('GlobalHashtagService Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late GlobalHashtagService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = GlobalHashtagService(firestore: fakeFirestore);
    });

    test('normalizeTag cleans and lowercases hashtag correctly', () {
      expect(GlobalHashtagService.normalizeTag('#OneOva'), 'oneova');
      expect(GlobalHashtagService.normalizeTag('###FlutterDev '), 'flutterdev');
      expect(GlobalHashtagService.normalizeTag('TRENDING_NOW'), 'trending_now');
      expect(GlobalHashtagService.normalizeTag('#'), '');
    });

    test('categorizeTag infers appropriate categories from keywords', () {
      expect(GlobalHashtagService.categorizeTag('technews'), 'technology');
      expect(GlobalHashtagService.categorizeTag('dancetrend'), 'dance');
      expect(GlobalHashtagService.categorizeTag('lofisong'), 'music');
      expect(GlobalHashtagService.categorizeTag('filmstudio'), 'creative');
      expect(GlobalHashtagService.categorizeTag('funnyvideo'), 'comedy');
      expect(GlobalHashtagService.categorizeTag('streetfashion'), 'lifestyle');
      expect(GlobalHashtagService.categorizeTag('randomtag'), 'general');
    });

    test('recordHashtagsUsed creates documents atomically and increments count', () async {
      await service.recordHashtagsUsed(['#oneova', '#flutter']);

      final oneovaDoc = await fakeFirestore.collection('hashtags').doc('oneova').get();
      expect(oneovaDoc.exists, isTrue);
      expect(oneovaDoc.data()?['tag'], 'oneova');
      expect(oneovaDoc.data()?['postCount'], 1);
      expect(oneovaDoc.data()?['velocityPerHour'], 1.0);

      // Record same tag again
      await service.recordHashtagsUsed(['#oneova']);
      final updatedDoc = await fakeFirestore.collection('hashtags').doc('oneova').get();
      expect(updatedDoc.data()?['postCount'], 2);
      expect(updatedDoc.data()?['velocityPerHour'], greaterThan(0.0));
    });

    test('searchHashtags finds tags by prefix and orders by postCount', () async {
      await service.recordHashtagsUsed(['#tech', '#techno', '#technology']);
      await service.recordHashtagsUsed(['#technology']); // 2 uses

      final results = await service.searchHashtags('tech');
      expect(results.length, 3);
      expect(results.first.tag, 'technology');
      expect(results.first.postCount, 2);
    });

    test('watchTrendingHashtags streams hashtags ordered by trendingScore', () async {
      await service.recordHashtagsUsed(['#viral', '#normal']);
      for (int i = 0; i < 4; i++) {
        await service.recordHashtagsUsed(['#viral']);
      }

      final streamList = await service.watchTrendingHashtags(limit: 5).first;
      expect(streamList.isNotEmpty, isTrue);
      expect(streamList.first.tag, 'viral');
    });
  });
}
