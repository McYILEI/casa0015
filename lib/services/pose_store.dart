import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Singleton that holds the reference pose detected from the uploaded image.
/// Both [UploadPage] (writer) and [CameraPage] (reader) share this instance.
class PoseStore extends ChangeNotifier {
  PoseStore._();
  static final PoseStore instance = PoseStore._();

  Pose? _referencePose;
  Size? _referenceImageSize;
  File? _referenceImage;

  Pose? get referencePose => _referencePose;
  Size? get referenceImageSize => _referenceImageSize;
  File? get referenceImage => _referenceImage;
  bool get hasReference => _referencePose != null;

  void setReference(Pose pose, Size imageSize, File image) {
    _referencePose = pose;
    _referenceImageSize = imageSize;
    _referenceImage = image;
    notifyListeners();
  }

  void clear() {
    _referencePose = null;
    _referenceImageSize = null;
    _referenceImage = null;
    notifyListeners();
  }
}
