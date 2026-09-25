/// A site sent back to the installer for rework (Tasks tab). Loaded from the
/// `reworkUrl` endpoint (rework_assign.php). The parser is tolerant of several
/// key names so the backend can send whatever column names it already uses.
class ReworkSite {
  final String id;
  final String siteName;
  final String address;
  final String contactNo;
  final String reason; // why it was sent back
  final String assignedOn; // date string, shown as-is
  final String brand;
  final String status;
  final String priority; // e.g. High / Normal
  final double? lat;
  final double? lng;

  const ReworkSite({
    required this.id,
    required this.siteName,
    this.address = '',
    this.contactNo = '',
    this.reason = '',
    this.assignedOn = '',
    this.brand = '',
    this.status = 'Pending',
    this.priority = '',
    this.lat,
    this.lng,
  });

  static String _s(Map j, List<String> keys) {
    for (final k in keys) {
      final v = j[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return '';
  }

  static double? _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  factory ReworkSite.fromJson(Map<String, dynamic> j) => ReworkSite(
        id: _s(j, ['id', 'recId', 'rec_id', 'siteId', 'reworkId']),
        siteName: _s(j,
            ['siteName', 'site_name', 'shopName', 'village', 'name', 'title']),
        address: _s(j, ['address', 'addr', 'location']),
        contactNo: _s(j, ['contactNo', 'ownerMobile', 'mobile', 'phone']),
        reason: _s(j, ['reason', 'reworkReason', 'rework_reason', 'remark', 'comment']),
        assignedOn: _s(j, ['assignedOn', 'assigned_on', 'date', 'assignedDate', 'reworkDate']),
        brand: _s(j, ['brand', 'brandName', 'project']),
        status: _s(j, ['status', 'reworkStatus']).isEmpty
            ? 'Pending'
            : _s(j, ['status', 'reworkStatus']),
        priority: _s(j, ['priority', 'reworkPriority']),
        lat: _d(j['lt'] ?? j['lat'] ?? j['latitude']),
        lng: _d(j['lg'] ?? j['lng'] ?? j['longitude']),
      );
}
