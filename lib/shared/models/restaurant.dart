class Restaurant {
  final int id;
  final String slug;
  final String name;
  final String? description;
  final String? logo;
  final String? address;
  final String? phone;
  final String? bankName;
  final String? bankAccount;
  final String? bankAccountName;
  final bool enableTableOrdering;
  final bool enableOnlineOrdering;
  final bool enableVietQr;
  final String? currency;

  const Restaurant({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.logo,
    this.address,
    this.phone,
    this.bankName,
    this.bankAccount,
    this.bankAccountName,
    this.enableTableOrdering = true,
    this.enableOnlineOrdering = false,
    this.enableVietQr = false,
    this.currency = 'VND',
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) => Restaurant(
        id: json['id'] as int,
        slug: json['slug'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        logo: json['logo'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        bankName: json['bank_name'] as String?,
        bankAccount: json['bank_account'] as String?,
        bankAccountName: json['bank_account_name'] as String?,
        enableTableOrdering: json['enable_table_ordering'] as bool? ?? true,
        enableOnlineOrdering: json['enable_online_ordering'] as bool? ?? false,
        enableVietQr: json['enable_viet_qr'] as bool? ?? false,
        currency: json['currency'] as String? ?? 'VND',
      );
}
