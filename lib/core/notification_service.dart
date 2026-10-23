import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  // Singleton pattern so the app uses the exact same service everywhere
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Your requested messages with emojis
  final List<String> messages = [
    "Alright Now You SHOULD study!! 😡📚",
    "Its been a while your books are crying 😭📖",
    "Hope you had loved the study as you loved sleeping 😴🛌",
    "Youtube Shorts and Reels wont make you trip to Europe ✈️🌍",
    "Relationship is crazier when its with pen and pencil ✏️❤️",
    "Hope you find a person in life who gives study advice 🎓🗣️",
    "Its already been a while you didnt study ⏳📉",
    "Do you have any future plan? 🤔🔮",
    "Are you serious about the exams? 📝🔥",
    "You have a whole syllabus to cover 🤯📑",
  ];

  Future<void> init() async {
    // Initialize timezone for background scheduling
    tz.initializeTimeZones();

    // Use the default Flutter app icon for the notification
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Request permission from the user (Required for Android 13+)
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> scheduleHourlyMotivation() async {
    // Clear old schedules first so we don't spam you if you open the app 5 times
    await flutterLocalNotificationsPlugin.cancelAll();

    final random = Random();

    // Schedule a notification for every hour for the next 48 hours
    for (int i = 1; i <= 48; i++) {
      String randomMessage = messages[random.nextInt(messages.length)];

      await flutterLocalNotificationsPlugin.zonedSchedule(
        i, // Unique ID for each hour
        'Cognire 🧠', // The title of the notification
        randomMessage, // The sassy message
        tz.TZDateTime.now(tz.local).add(Duration(hours: i)), // Schedule it 'i' hours from now
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'study_motivation_channel',
            'Study Motivation',
            channelDescription: 'Hourly reminders to stop procrastinating',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, // Allows it to work even in battery saver
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}