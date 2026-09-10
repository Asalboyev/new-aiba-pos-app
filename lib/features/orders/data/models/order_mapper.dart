import '../../domain/entities/order_draft.dart';

/// Maps domain order objects to the backend `OrderIn` JSON shape and parses
/// `serialize_order` responses. Pure functions — unit tested.
class OrderMapper {
  const OrderMapper._();

  /// Build the `OrderIn` payload for POST /orders and /sync/push.
  ///
  /// Money is sent as plain numbers (so'm, no tiyin). Only non-null optional
  /// fields are included to keep the payload clean.
  static Map<String, dynamic> draftToOrderIn(OrderDraft draft) {
    return {
      'client_uuid': draft.clientUuid,
      if (draft.number != null && draft.number!.isNotEmpty)
        'number': draft.number,
      if (draft.tableNo != null && draft.tableNo!.isNotEmpty)
        'table_no': draft.tableNo,
      if (draft.note != null && draft.note!.isNotEmpty) 'note': draft.note,
      if (draft.shiftId != null && draft.shiftId!.isNotEmpty) 'shift_id': draft.shiftId,
      'discount': draft.discount,
      'items': [
        for (final item in draft.items)
          {
            if (item.productId != null) 'product_id': item.productId,
            'name': item.name,
            'qty': item.qty,
            'price': item.price,
            if (item.mxikCode != null) 'mxik_code': item.mxikCode,
            if (item.packageCode != null) 'package_code': item.packageCode,
            if (item.vatPercent != null) 'vat_percent': item.vatPercent,
            // E-POS markirovka mahsulotlari uchun marka kodi majburiy.
            // IKKI DONA sotilsa IKKALA kod ham ketishi kerak — soliqqa qaysi
            // donalar sotilgani ko'rinib tursin. Ilgari faqat `labels.first`
            // jo'natilardi: kassir ikkita shishani skanerlasa, chekda bitta
            // marka kodi qolib, ikkinchisi yo'qolardi.
            //
            // Server `label` (bitta) va `labels` (ro'yxat) — ikkalasini ham
            // biladi, LEKIN `label` ustun turadi. Shuning uchun bittasini
            // jo'natamiz: bir dona bo'lsa `label`, ko'p bo'lsa `labels`.
            if (item.labels.length == 1) 'label': item.labels.first,
            if (item.labels.length > 1) 'labels': item.labels,
          },
      ],
      'payments': [
        for (final p in draft.payments)
          {'method': p.method.code, 'amount': p.amount, 'label': p.label},
      ],
    };
  }

  /// Extract the order id from a /orders create response.
  static String? orderId(Map<String, dynamic> response) {
    final order = (response['order'] as Map?)?.cast<String, dynamic>();
    return order?['id']?.toString();
  }

  /// Extract the order number from a /orders create response.
  static String? orderNumber(Map<String, dynamic> response) {
    final order = (response['order'] as Map?)?.cast<String, dynamic>();
    return order?['number']?.toString();
  }

  /// Extract the fiscal map from a /orders create response (may be null).
  static Map<String, dynamic>? fiscalMap(Map<String, dynamic> response) {
    final order = (response['order'] as Map?)?.cast<String, dynamic>();
    final fiscal = order?['fiscal'];
    return (fiscal is Map) ? fiscal.cast<String, dynamic>() : null;
  }
}
