import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/features/email/presentation/widgets/pdf_viewer/pdf_encryption_detector.dart';

Uint8List _bytes(String content) => Uint8List.fromList(latin1.encode(content));

void main() {
  group('isEncryptedPdf', () {
    test('returns true when trailer references an /Encrypt indirect object', () {
      final pdf = _bytes(
        '%PDF-1.7\n'
        'trailer\n'
        '<< /Root 1 0 R /Encrypt 12 0 R /Size 20 >>\n'
        'startxref\n1234\n%%EOF',
      );

      expect(isEncryptedPdf(pdf), isTrue);
    });

    test('is tolerant of extra whitespace in the /Encrypt reference', () {
      final pdf = _bytes('%PDF-1.5\n<< /Encrypt   8   0   R >>');

      expect(isEncryptedPdf(pdf), isTrue);
    });

    test('returns false for a normal PDF without /Encrypt', () {
      final pdf = _bytes(
        '%PDF-1.7\n'
        'trailer\n'
        '<< /Root 1 0 R /Size 20 >>\n'
        'startxref\n1234\n%%EOF',
      );

      expect(isEncryptedPdf(pdf), isFalse);
    });

    test('returns false when /Encrypt appears without an indirect ref shape', () {
      // Bare token that is not a valid encryption dictionary reference.
      final pdf = _bytes('%PDF-1.7\n<< /Encrypt true >>');

      expect(isEncryptedPdf(pdf), isFalse);
    });

    test('returns false for empty bytes', () {
      expect(isEncryptedPdf(Uint8List(0)), isFalse);
    });

    test('returns false for arbitrary non-PDF bytes', () {
      expect(isEncryptedPdf(Uint8List.fromList([0, 1, 2, 3, 255, 254])), isFalse);
    });
  });
}
