import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meshagent/runtime.dart';

import 'runtime_impl.dart' if (dart.library.io) 'runtime_native.dart' if (dart.library.js_interop) 'runtime_web.dart';

Future initializeFlutterDocumenRuntime() async {
  WidgetsFlutterBinding.ensureInitialized();

  DocumentRuntime.instance = DocumentRuntimeImpl();
  initializeDocumentRuntime();
}
