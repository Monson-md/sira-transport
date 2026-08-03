import 'package:cloud_firestore/cloud_firestore.dart';

class RideMessageModel {
  final String id;
  final String senderId;
  final String text;
  final DateTime? createdAt;

  const RideMessageModel({
    required this.id,
    required this.senderId,
    required this.text,
    this.createdAt,
  });

  factory RideMessageModel.fromMap(String id, Map<String, dynamic> map) {
    final createdAtValue = map['createdAt'];
    return RideMessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      text: map['text'] ?? '',
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'text': text,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
    };
  }
}
