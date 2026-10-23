import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/ova_assistant/services/ova_local_intents.dart';

void main() {
  OvaLocalIntent? p(String s) => OvaLocalIntents.parse(s);

  test('calls and messages', () {
    expect(p('call Mum')!.tool, 'call_phone');
    expect(p('call Mum')!.args['to'], 'Mum');
    final sms = p('text Brian saying running 5 min late')!;
    expect(sms.tool, 'send_sms');
    expect(sms.args, {'to': 'Brian', 'body': 'running 5 min late'});
    expect(p('message @amina hey there')!.args, {'username': 'amina', 'text': 'hey there'});
    expect(p('whatsapp +254700000000 saying hi')!.tool, 'send_whatsapp');
  });

  test('in-app navigation and social', () {
    expect(p('go live')!.args['screen'], 'go_live');
    expect(p('start live studio')!.args['screen'], 'live_studio');
    expect(p('open messages')!.args['screen'], 'messages');
    expect(p('Ova, open notifications')!.args['screen'], 'notifications');
    expect(p('search for #music')!.args['query'], '#music');
    expect(p('follow @amina')!.tool, 'follow_user');
    expect(p('like this')!.tool, 'like_current_reel');
    expect(p('upload a video')!.args['screen'], 'upload');
  });

  test('device abilities', () {
    expect(p('flashlight on')!.args['on'], true);
    expect(p('turn off the torch')!.args['on'], false);
    expect(p('volume 40')!.args['percent'], 40);
    expect(p('set brightness to 80%')!.args['percent'], 80);
    expect(p('set an alarm for 7:30 pm')!.args, {'hour': 19, 'minute': 30, 'label': ''});
    expect(p('set a timer for 5 minutes')!.args['seconds'], 300);
    expect(p('remind me to drink water in 10 min')!.tool, 'set_reminder');
    expect(p('where am i')!.tool, 'get_location');
    expect(p('take a photo')!.tool, 'take_photo');
    expect(p('open youtube')!.args['app'], 'youtube');
    expect(p('open settings')!.tool, 'open_settings');
    expect(p('open oneova.studio')!.tool, 'open_url');
  });

  test('device awareness and settings', () {
    expect(p('read my notifications')!.tool, 'read_notifications');
    expect(p("what's new")!.tool, 'read_notifications');
    expect(p('check whatsapp messages')!.args['app'], 'whatsapp');
    expect(p('read my sms'), isNull); // no SMS reading (Play policy)
    expect(p('pause the music')!.args['action'], 'pause');
    expect(p('next song')!.args['action'], 'next');
    expect(p('turn on do not disturb')!.args['on'], true);
    expect(p('silent mode')!.args['mode'], 'silent');
    expect(p('dark mode')!.args['mode'], 'dark');
    expect(p('turn on wifi')!.args['panel'], 'wifi');
  });

  test('ambiguous text goes to the model', () {
    expect(p('what should I post today?'), isNull);
    expect(p('find my phone'), isNull);
    expect(p('write me a caption about sunsets'), isNull);
  });

  test('location, memory and reminders', () {
    expect(p('where am i')!.tool, 'get_location');
    expect(p("what's near me")!.tool, 'find_nearby');
    expect(p('coffee near me')!.args['what'], 'coffee');
    expect(p('find a pharmacy nearby')!.args['what'], 'pharmacy');
    expect(p('nearest ATM')!.args['what'], 'ATM');
    expect(p('navigate to Westgate Mall')!.args, {'destination': 'Westgate Mall', 'mode': 'driving'});
    expect(p('walk to the park')!.args['mode'], 'walking');
    expect(p('how is my signal')!.tool, 'check_signal');
    expect(p('what was I working on')!.tool, 'recent_activity');
    expect(p('my reminders')!.tool, 'list_reminders');
    expect(p('cancel reminder about the reel')!.args['query'], 'the reel');
    final r = p('remind me to post the reel at 6:30 pm')!;
    expect(r.tool, 'set_reminder');
    expect(r.args['text'], 'post the reel');
    final at = DateTime.parse(r.args['at'] as String);
    expect(at.hour, 18);
    expect(at.minute, 30);
    expect(at.isAfter(DateTime.now()), isTrue);
  });

  test('connected accounts', () {
    expect(p('check my email')!.tool, 'gmail_inbox');
    expect(p('any new emails')!.tool, 'gmail_inbox');
    expect(p('youtube stats')!.tool, 'youtube_channel');
    expect(p('my latest youtube comments')!.tool, 'youtube_comments');
    expect(p('show my facebook page')!.tool, 'facebook_page');
    expect(p('facebook comments')!.tool, 'facebook_comments');
  });
}
