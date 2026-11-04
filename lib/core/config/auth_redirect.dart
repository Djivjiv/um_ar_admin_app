/// Where the router sends someone, or null to let them stay. Only a confirmed
/// admin gets past `/login`: a session alone isn't enough, because a non-admin
/// has one for a moment while signing in.
String? adminRedirect({
  required bool hasSession,
  required bool isAdmin,
  required bool atLogin,
}) {
  if (!hasSession || !isAdmin) return atLogin ? null : '/login';
  return atLogin ? '/dashboard' : null;
}
