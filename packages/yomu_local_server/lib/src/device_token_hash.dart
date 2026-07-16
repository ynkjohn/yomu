import 'dart:convert';

import 'package:crypto/crypto.dart';

String hashDeviceBearer(String token) {
  return sha256.convert(utf8.encode(token)).toString();
}
