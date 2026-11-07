// =====================================================================
// App configuration
// ---------------------------------------------------------------------
// Paste your Supabase project's URL and "anon public" key below
// (Supabase → Project Settings → API). The anon key is safe to keep in
// the app; NEVER put the "service_role" key here.
//
// Or leave these empty and add GitHub secrets SUPABASE_URL and
// SUPABASE_ANON_KEY — the automatic build passes them in.
// =====================================================================

const String _pastedUrl = 'https://xcooxtqusidhbzduwwgm.supabase.co'; // e.g. 'https://abcdxyz.supabase.co'
const String _pastedAnonKey = 'sb_publishable_m3NQWTikrplsZGv9CKLudw_zdY5nhDX'; // publishable key: safe in the app // e.g. 'eyJhbGciOi...'

const String _envUrl = String.fromEnvironment('SUPABASE_URL');
const String _envAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

const String supabaseUrl = _envUrl != '' ? _envUrl : _pastedUrl;
const String supabaseAnonKey = _envAnonKey != '' ? _envAnonKey : _pastedAnonKey;

const String appName = 'Meloria Clinic';
const String clinicLegalName = 'Meloria Siddha and Varma Clinic';
const int currentBranchId = 1;

bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
