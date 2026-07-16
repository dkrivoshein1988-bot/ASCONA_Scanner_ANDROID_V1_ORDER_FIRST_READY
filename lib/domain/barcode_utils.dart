String cleanScannedValue(String value) {
  return value.replaceAll(RegExp(r'[\u0000-\u001F]'), '').trim();
}

String normalizeProductBarcode(String value) {
  return cleanScannedValue(value).replaceAll(RegExp(r'\s+'), '').toUpperCase();
}

