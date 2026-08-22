import 'package:flutter/material.dart';
import 'app.dart';
import 'native/classroom_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ClassroomEngine.instance = await ClassroomEngine.init();
  runApp(const ClassRoomApp());
}
