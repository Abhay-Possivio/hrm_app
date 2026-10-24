/// Role checks on the /accounts/me/ response, the same ones AppRouter.tsx,
/// ProtectedRoute.tsx and the two sidebars use.
extension UserRole on Map<String, dynamic> {
  bool get isSuperuser => this['is_superuser'] == true;
  bool get isCompanyAdmin => this['is_company_admin'] == true;
  bool get isEmployeePortal => this['is_employee_portal'] == true;
  bool get isTeamLead => this['role'] == 'TEAM_LEAD';

  String get username => '${this['username'] ?? ''}';

  String get companyName {
    final name = '${this['company_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Workforce' : name;
  }
}