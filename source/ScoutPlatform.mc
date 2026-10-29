// Build-time switches. tools/run_sim_session.sh copies sim/ScoutPlatform.mc
// over this file for the virtual-G7 simulator build.
class ScoutPlatform {
    // The app-start "who collects" query to the phone (ScoutCollector). The
    // simulator answers a transmit with a modal "no data connection" dialog
    // that blocks the run, so its build turns this off.
    static const PHONE_QUERY_AT_START = true;
}
