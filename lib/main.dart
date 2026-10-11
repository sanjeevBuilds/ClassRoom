import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'native/classroom_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  ClassroomEngine.instance = await ClassroomEngine.init();
  runApp(const ClassRoomApp());
}
