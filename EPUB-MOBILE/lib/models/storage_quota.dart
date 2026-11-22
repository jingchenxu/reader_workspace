class StorageQuota {
  const StorageQuota({
    required this.usedBytes,
    required this.quotaBytes,
    required this.remainingBytes,
    required this.membershipType,
    required this.unlimited,
  });

  final int usedBytes;
  final int quotaBytes;
  final int remainingBytes;
  final String membershipType;
  final bool unlimited;

  double get usageRatio {
    if (unlimited || quotaBytes <= 0) return 0;
    return (usedBytes / quotaBytes).clamp(0, 1);
  }

  factory StorageQuota.fromJson(Map<String, dynamic> json) {
    return StorageQuota(
      usedBytes: _intValue(json['usedBytes'] ?? json['used_bytes']),
      quotaBytes: _intValue(json['quotaBytes'] ?? json['quota_bytes']),
      remainingBytes: _intValue(
        json['remainingBytes'] ?? json['remaining_bytes'],
      ),
      membershipType:
          (json['membershipType'] ?? json['membership_type'] ?? 'READER')
              .toString(),
      unlimited: _boolValue(json['unlimited']),
    );
  }

  static int _intValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static bool _boolValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value?.toString().toLowerCase() == 'true';
  }
}
