class ReturnRecord {
  const ReturnRecord({
    required this.id,
    required this.createdAt,
    required this.marketplace,
    required this.operatorName,
    required this.shift,
    required this.orderCode,
    required this.itemCode,
    required this.itemName,
    required this.condition,
    required this.comment,
  });

  final String id;
  final DateTime createdAt;
  final String marketplace;
  final String operatorName;
  final String shift;
  final String orderCode;
  final String itemCode;
  final String itemName;
  final String condition;
  final String comment;

  bool get hasProblem => condition != 'Принят';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'marketplace': marketplace,
      'operatorName': operatorName,
      'shift': shift,
      'orderCode': orderCode,
      'itemCode': itemCode,
      'itemName': itemName,
      'condition': condition,
      'comment': comment,
    };
  }

  factory ReturnRecord.fromJson(Map<String, dynamic> json) {
    return ReturnRecord(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      marketplace: json['marketplace'] as String? ?? 'OZON',
      operatorName: json['operatorName'] as String? ?? '',
      shift: json['shift'] as String? ?? 'День',
      orderCode: (json['orderCode'] as String?) ??
          (json['returnCode'] as String?) ??
          '',
      itemCode: json['itemCode'] as String? ?? '',
      itemName: json['itemName'] as String? ?? '',
      condition: json['condition'] as String? ?? 'Принят',
      comment: json['comment'] as String? ?? '',
    );
  }

  ReturnRecord copyWith({
    String? marketplace,
    String? operatorName,
    String? shift,
    String? orderCode,
    String? itemCode,
    String? itemName,
    String? condition,
    String? comment,
  }) {
    return ReturnRecord(
      id: id,
      createdAt: createdAt,
      marketplace: marketplace ?? this.marketplace,
      operatorName: operatorName ?? this.operatorName,
      shift: shift ?? this.shift,
      orderCode: orderCode ?? this.orderCode,
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      condition: condition ?? this.condition,
      comment: comment ?? this.comment,
    );
  }
}
