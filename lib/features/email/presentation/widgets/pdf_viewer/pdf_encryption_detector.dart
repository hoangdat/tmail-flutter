import 'dart:convert';
import 'dart:typed_data';

/// Matches the PDF encryption dictionary reference in the trailer, e.g.
/// `/Encrypt 12 0 R`. The `/Encrypt` entry points to an indirect object
/// (`objNum genNum R`), so requiring that `N G R` shape makes the check far
/// more specific than a bare `/Encrypt` substring and avoids matching the
/// literal bytes appearing incidentally inside a stream.
final RegExp _encryptDictRefPattern = RegExp(r'/Encrypt\s+\d+\s+\d+\s+R');

/// Heuristic detection of a password-protected (encrypted) PDF from its raw
/// bytes, without fully parsing the document.
///
/// Used to short-circuit the web previewer before handing encrypted bytes to
/// pdfrx (which would otherwise render its raw error banner), so we can show a
/// friendly "download to open" message instead.
///
/// Limitations (acceptable for this use):
/// - False positive: a normal PDF whose bytes happen to contain the exact
///   `/Encrypt N G R` sequence is downgraded to the friendly message. Very rare.
/// - False negative: a PDF using a direct (non-indirect) `/Encrypt` dictionary
///   is not detected and falls back to pdfrx's default behaviour. Very rare.
bool isEncryptedPdf(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  // latin1 with allowInvalid maps every byte 1:1 to a code unit, so the regex
  // scans the raw byte stream without throwing on non-text bytes.
  final content = latin1.decode(bytes, allowInvalid: true);
  return _encryptDictRefPattern.hasMatch(content);
}
