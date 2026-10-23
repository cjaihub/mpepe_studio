// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/telemetry/apm_service.dart';

void main() {
  group('APM Benchmark Suite', () {
    late ApmService apm;

    setUp(() {
      apm = ApmService();
    });

    test('Simulate unoptimized database query (N+1 problem)', () async {
      // Simulate N+1 query pattern often found in naive message feeds
      apm.startTrace('db_query_time');
      
      // Simulate fetching 100 messages
      await Future.delayed(const Duration(milliseconds: 50)); 
      
      for (int i = 0; i < 50; i++) {
        // Simulate fetching author profile for each message individually (N+1)
        apm.startTrace('db_query_user_profile_\$i');
        await Future.delayed(const Duration(milliseconds: 15));
        apm.stopTrace('db_query_user_profile_\$i');
        
        // Feed into total latency
        apm.recordLatency('api_response_time', 15); 
      }
      
      apm.stopTrace('db_query_time');
      
      // We expect the total db_query_time to be > 800ms
      final report = apm.generateReportJson();
      expect(report['db_query_time']['avg'], greaterThan(700.0));
      
      print('--- Pre-Optimization Benchmark ---');
      apm.printOptimizationReport();
    });

    test('Simulate optimized database query (Event Batching & Caching)', () async {
      // Simulate optimized pattern
      apm.startTrace('db_query_time_optimized');
      
      // Fetch 100 messages
      await Future.delayed(const Duration(milliseconds: 50)); 
      
      // Extract unique author IDs and batch fetch (in-clauses limit 10)
      // Memoization / Caching used for already fetched profiles
      apm.startTrace('db_query_batched_profiles');
      await Future.delayed(const Duration(milliseconds: 40)); // Batched network trip
      apm.stopTrace('db_query_batched_profiles');
      
      apm.stopTrace('db_query_time_optimized');
      
      final report = apm.generateReportJson();
      expect(report['db_query_time_optimized']['avg'], lessThan(200.0));
      
      print('--- Post-Optimization Benchmark ---');
      apm.printOptimizationReport();
    });
  });
}
