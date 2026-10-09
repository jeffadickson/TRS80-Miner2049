// m3test: the Miner 2049er (TRS-80 Model III) playtester, native.
//
// A C++ port of tools/m3.py, explore.py and playthrough.py.  It uses the same Z80 core
// (Ivan Kosarev's z80.h, MIT licence) that the Python `z80` package wraps, with the same
// frame timing, so it plays the game exactly as the Python tester does: the explorer finds
// the same nodes, the playthrough makes the same moves.  The differences are speed (no
// Python callbacks; snapshots are a memcpy) and one optional shortcut, the idle skip: the
// game spends 40-60% of every frame in WAITTICK polling port $E0 for the next clock tick;
// with the sound queue empty that loop changes nothing but A, F, WZ and R, so it can be
// jumped over in one step with those four set exactly as running it would have left them.
// --check runs both ways and compares every byte of the machine after each frame.
//
//   m3test explore 1 5 8 [-j N]          what Bob can reach (mutants off)
//   m3test play 3 4 [-m] [-v] [-f] [-j N] play stations through (-m mutants, -f freeze bonus)
//   m3test check 1 [frames]              idle skip vs. none, byte for byte
//   m3test trace 1 [frames]              a hash of the machine after each frame
//   --no-skip   run the idle loop instead of skipping it
//   --backtracks N   give up after N back-ups (default 60)
//   --lst F / --cmd F                    default ../../build/miner3.lst, ../../build/miner3.cmd
//
// Build: g++ -O2 -std=c++17 -o m3test m3test.cpp -lz -lpthread

#include "z80.h"
#include <zlib.h>
#include <algorithm>
#include <array>
#include <cstdarg>
#include <cctype>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using std::string;
using std::vector;

static const long CLOCK = 2027520;
static const long TICK = CLOCK / 30;      // 67,584 T-states per 1/30 s

// ---- symbols, from the assembler listing --------------------------------------------
static std::map<string, int> SYM;
static int S(const char *n) {
    auto it = SYM.find(n);
    if (it == SYM.end()) { fprintf(stderr, "symbol %s not in the listing\n", n); exit(2); }
    return it->second;
}
static void load_syms(const string &path) {
    std::ifstream f(path);
    if (!f) { fprintf(stderr, "cannot open %s\n", path.c_str()); exit(2); }
    std::regex re(R"(\s([0-9A-F]{4})\s+(?:[0-9A-F]{2,8}\s*)?\t([A-Za-z_][A-Za-z0-9_]*):)");
    string l; std::smatch m;
    while (std::getline(f, l))
        if (std::regex_search(l, m, re)) SYM[m[2]] = std::stoi(m[1], nullptr, 16);
}

// the addresses the tester reads, looked up once
static int A_BOBX, A_BOBY, A_BOBSTATE, A_STATION, A_SECTIONS, A_MUTTAB, A_BONUS, A_BONUSTMR,
    A_LIFTON, A_LIFTX, A_LIFTROW, A_LIFTDRV, A_TNT, A_CANX, A_PLATTAB, A_NPLAT, A_PULVON,
    A_TRANSON, A_TRLOCK, A_NITEMS, A_ITEMTAB, A_WT0, A_SNDN;
static void bind_syms() {
    A_BOBX = S("BOBX"); A_BOBY = S("BOBY"); A_BOBSTATE = S("BOBSTATE"); A_STATION = S("STATION");
    A_SECTIONS = S("SECTIONS"); A_MUTTAB = S("MUTTAB"); A_BONUS = S("BONUS"); A_BONUSTMR = S("BONUSTMR");
    A_LIFTON = S("LIFTON"); A_LIFTX = S("LIFTX"); A_LIFTROW = S("LIFTROW"); A_LIFTDRV = S("LIFTDRV");
    A_TNT = S("TNT"); A_CANX = S("CANX"); A_PLATTAB = S("PLATTAB"); A_NPLAT = S("NPLAT");
    A_PULVON = S("PULVON"); A_TRANSON = S("TRANSON"); A_TRLOCK = S("TRLOCK"); A_NITEMS = S("NITEMS");
    A_ITEMTAB = S("ITEMTAB"); A_WT0 = S("WT0"); A_SNDN = S("SNDN");
}

// ---- keys ---------------------------------------------------------------------------
// a key set is a bitmask over these
enum { K_ENTER, K_UP, K_DOWN, K_LEFT, K_RIGHT, K_SPACE, K_1, K_2, K_3, K_4, K_DIGIT0 };
static const char *KNAME[] = {"ENTER", "UP", "DOWN", "LEFT", "RIGHT", "SPACE", "1", "2", "3", "4"};
static int key_row_bit(int k, int &bit) {   // (row bit, bit) as m3.py's KEYS
    switch (k) {
    case K_ENTER: bit = 0; return 0x40;
    case K_UP: bit = 3; return 0x40;
    case K_DOWN: bit = 4; return 0x40;
    case K_LEFT: bit = 5; return 0x40;
    case K_RIGHT: bit = 6; return 0x40;
    case K_SPACE: bit = 7; return 0x40;
    }
    int d = k - K_DIGIT0;                   // digits 0-9
    bit = d % 8; return d < 8 ? 0x10 : 0x20;
}
static uint32_t KB(int k) { return 1u << k; }
static uint32_t KDIGIT(int d) { return 1u << (K_DIGIT0 + d); }

// ---- the machine ---------------------------------------------------------------------
struct M3 : public z80::z80_cpu<M3> {
    typedef z80::z80_cpu<M3> base;
    uint8_t mem[65536];
    uint8_t kbd[256];          // keyboard matrix read value for each low address byte
    uint8_t rtc = 0;
    int64_t ticks_left = 0;
    static bool skip_idle;

    M3() { memset(mem, 0, sizeof mem); memset(kbd, 0, sizeof kbd); set_af(0x0002); }

    z80::fast_u8 on_read(z80::fast_u16 a) {
        if (a >= 0x3800 && a < 0x3C00) return kbd[a & 0xFF];
        return mem[a];
    }
    void on_write(z80::fast_u16 a, z80::fast_u8 n) { mem[a] = (uint8_t)n; }
    z80::fast_u8 on_input(z80::fast_u16 port) {
        unsigned p = port & 0xFF;
        if (p == 0xE0) return rtc ? 0xFB : 0xFF;      // active low
        if (p == 0xEC) { rtc = 0; return 0xFF; }
        if (p == 0xFF) return 0x00;
        return 0xFF;
    }
    void on_output(z80::fast_u16, z80::fast_u8) {}
    void on_tick(unsigned t) { ticks_left -= t; }

    void set_keys(uint32_t keys) {
        int rows[16], bits[16], n = 0;
        for (int k = 0; k < 32; k++)
            if (keys & (1u << k)) { rows[n] = key_row_bit(k, bits[n]); n++; }
        for (int a = 0; a < 256; a++) {
            int v = 0;
            for (int i = 0; i < n; i++) if (a & rows[i]) v |= 1 << bits[i];
            kbd[a] = (uint8_t)v;
        }
    }

    void load_cmd(const string &path) {
        std::ifstream f(path, std::ios::binary);
        if (!f) { fprintf(stderr, "cannot open %s\n", path.c_str()); exit(2); }
        vector<uint8_t> d((std::istreambuf_iterator<char>(f)), {});
        size_t i = 0; int entry = 0;
        while (i + 1 < d.size()) {
            int typ = d[i], ln = d[i + 1]; i += 2;
            if (ln == 0 && typ == 1) ln = 256;
            if (typ == 1) {
                int n = ln > 2 ? ln : ln + 256;
                int addr = d[i] | d[i + 1] << 8;
                for (int j = 2; j < n && i + j < d.size(); j++) mem[(addr + j - 2) & 0xFFFF] = d[i + j];
                i += n;
            } else if (typ == 2) { entry = d[i] | d[i + 1] << 8; break; }
            else i += ln;
        }
        set_pc(entry); set_sp(0xFFF0);
    }

    // one 1/30 s period: instructions until the period's T-states are used up (the
    // instruction that crosses the line finishes; the overshoot is dropped, as in m3.py)
    void run_frame() {
        ticks_left = TICK;
        const int wt0 = A_WT0, sndn = A_SNDN;
        while (ticks_left > 0) {
            if (skip_idle && get_pc() == wt0 && !rtc && mem[sndn] == 0) {
                // WT0: in a,($E0) 11 / and 4 7 / jr z 7 / ld a,(SNDN) 13 / or a 4 / jr z,WT0 12:
                // 54 T and 6 opcode fetches a turn, ending with A = 0, F = 44h (or a), WZ = WT0
                int64_t n = (ticks_left - 1) / 54;   // whole turns that end inside the frame
                if (n > 0) {
                    ticks_left -= 54 * n;
                    unsigned r = get_r();
                    set_r((r & 0x80) | ((r + 6 * n) & 0x7F));
                    set_a(0); set_f(0x44); set_wz(wt0);
                }
                if (ticks_left <= 0) break;
            }
            on_step();
        }
        rtc = 1;
    }
};
bool M3::skip_idle = true;

// ---- snapshots ------------------------------------------------------------------------
// the whole machine object (CPU state, memory, keyboard, flags) XORed with the image taken
// when the station started, zlib-compressed: about 0.5 KB
static_assert(std::is_trivially_copyable<M3>::value, "M3 must be copyable as bytes");
struct Snap {
    string z;
    int frames = 0;
    int station = 0, sections = 0, bobx = 0, boby = 0, bobstate = 0;
};

struct Game {
    M3 h;
    std::shared_ptr<vector<uint8_t>> ref;
    int st; bool freeze;
    long frames = 0, total = 0;
    vector<uint8_t> buf, xbuf;

    Game(int st, const string &cmd, bool mutants = false, int freeze_ = -1) : st(st) {
        h.load_cmd(cmd);
        run(20); run(3, KDIGIT(st % 10)); run(3); run(3, KB(K_SPACE));
        run(80);
        freeze = freeze_ < 0 ? !mutants : freeze_ != 0;
        if (!mutants) quiet();
        if (freeze) setv(A_BONUS, 0x99);
        frames = 0; total = 0;
    }
    int v(int a) const { return h.mem[a]; }
    void setv(int a, int x) { h.mem[a] = (uint8_t)x; }
    void quiet() { for (int k = 0; k < 8; k++) h.mem[A_MUTTAB + k * 10 + 7] = 0; }
    void run(int n, uint32_t keys = 0) { h.set_keys(keys); for (int i = 0; i < n; i++) h.run_frame(); }
    int frame(uint32_t keys = 0) {
        h.set_keys(keys); h.run_frame();
        frames++; total++;
        if (freeze) setv(A_BONUSTMR, 0);
        return v(A_BOBSTATE);
    }
    const uint8_t *bytes() const { return reinterpret_cast<const uint8_t *>(&h); }
    Snap snap() {
        const size_t n = sizeof(M3);
        if (!ref) ref = std::make_shared<vector<uint8_t>>(bytes(), bytes() + n);
        xbuf.resize(n);
        const uint8_t *b = bytes(), *r = ref->data();
        for (size_t i = 0; i < n; i++) xbuf[i] = b[i] ^ r[i];
        uLongf zn = compressBound(n); buf.resize(zn);
        compress2(buf.data(), &zn, xbuf.data(), n, 1);
        Snap s; s.z.assign((char *)buf.data(), zn); s.frames = frames;
        s.station = v(A_STATION); s.sections = v(A_SECTIONS) | v(A_SECTIONS + 1) << 8;
        s.bobx = v(A_BOBX); s.boby = v(A_BOBY); s.bobstate = v(A_BOBSTATE);
        return s;
    }
    void restore(const Snap &s) {
        const size_t n = sizeof(M3);
        uLongf zn = n; xbuf.resize(n);
        uncompress(xbuf.data(), &zn, (const Bytef *)s.z.data(), s.z.size());
        uint8_t *b = reinterpret_cast<uint8_t *>(&h); const uint8_t *r = ref->data();
        for (size_t i = 0; i < n; i++) b[i] = xbuf[i] ^ r[i];
        frames = s.frames;
    }
    // memory as it is in a snapshot, without touching the live machine
    vector<uint8_t> image(const Snap &s) {
        const size_t n = sizeof(M3);
        vector<uint8_t> out(n); uLongf zn = n;
        uncompress(out.data(), &zn, (const Bytef *)s.z.data(), s.z.size());
        const uint8_t *r = ref->data();
        for (size_t i = 0; i < n; i++) out[i] ^= r[i];
        return out;
    }
    static size_t mem_off() { static M3 *p = nullptr; static size_t o = 0; if (!p) { p = new M3; o = (const uint8_t *)p->mem - (const uint8_t *)p; } return o; }

    enum { GROUND, JUMP, FALL, LADDER, SLIDE, DYING, TRANS, CANNON, FLY };
    vector<int> key(bool mutants = true) const {
        int x = v(A_BOBX), feet = v(A_BOBY) + 6, s = v(A_BOBSTATE);
        vector<int> k{x, feet, s};
        if (st == 10) { k.push_back(v(A_TNT)); k.push_back(s == CANNON ? v(A_CANX) : 0); }
        if (onlift()) {
            int lx = v(A_LIFTX);
            k = {x - lx, feet, s, -1000 /* 'lift' */, lx / 4, v(A_LIFTROW)};
        }
        for (int i = 0; i < v(A_NPLAT); i++) {
            int P = A_PLATTAB + i * 11;
            int px = h.mem[P], row = h.mem[P + 1], w = h.mem[P + 2], d = h.mem[P + 5];
            if (s == GROUND && feet == row && x + 3 >= px && x + 2 < px + w) {
                k.push_back(-2000 /* 'plat' */); k.push_back(i); k.push_back(px); k.push_back(d);
            }
        }
        // live mutants on his floor or the next ones (within 12 rows), coarsely: where they
        // are (8-block steps) and which way they walk.  Without this, waiting for one to pass
        // brings Bob back to a place already seen and the search throws it away
        for (int i = 0; i < (mutants ? 8 : 0); i++) {
            const uint8_t *mu = h.mem + A_MUTTAB + i * 10;
            if (mu[7] && std::abs(mu[1] - feet) <= 12) {
                k.push_back(-3000 /* 'mut' */); k.push_back(i); k.push_back(mu[0] / 8); k.push_back(mu[4]);
            }
        }
        return k;
    }
    bool onlift() const {
        if (!v(A_LIFTON) || v(A_BOBSTATE) != GROUND) return false;
        int x = v(A_BOBX), feet = v(A_BOBY) + 6, lx = v(A_LIFTX);
        return feet == v(A_LIFTROW) && x + 3 >= lx && x < lx + 14;
    }
    int settle(int limit = 300) {
        for (int i = 0; i < limit; i++) {
            int s = v(A_BOBSTATE);
            if ((s == GROUND || s == CANNON || s == DYING) && i > 0) return s;
            frame();
        }
        return v(A_BOBSTATE);
    }
};

struct KeyHash {
    size_t operator()(const vector<int> &k) const {
        size_t h = 1469598103934665603ull;
        for (int x : k) { h ^= (size_t)(x + 0x9e3779b9); h *= 1099511628211ull; }
        return h;
    }
};

// ---- the explorer ---------------------------------------------------------------------
struct Action {
    enum T { START, WALK, JUMP, CLIMB, WAIT, TRANS, DRIVE, FIRE, ROLL } t;
    int a = 0, n = 0;
    string str() const {
        switch (t) {
        case START: return "start";
        case WALK: return string("walk ") + KNAME[a];
        case JUMP: return a < 0 ? "jump up" : string("jump ") + KNAME[a];
        case CLIMB: return string("climb ") + KNAME[a];
        case WAIT: return "wait " + std::to_string(n);
        case TRANS: return "transporter " + std::to_string(a);
        case DRIVE: return string("drive ") + KNAME[a] + " " + std::to_string(n);
        case FIRE: return "fire";
        case ROLL: return string("roll ") + KNAME[a];
        }
        return "?";
    }
};

struct Explorer {
    struct Node { Snap snap; int parent; Action act; };
    Game *g; int st; const Snap *root;
    vector<int> gaps, items;
    vector<char> claimed_flag; int nclaimed = 0;
    vector<int> open_gaps, open_items;
    std::unordered_set<int> collected;
    std::unordered_map<vector<int>, int, KeyHash> ids;      // every key seen -> id
    vector<int> node_of;                                     // id -> node index or -1
    vector<Node> nodes;
    vector<vector<char>> items_at;                           // node -> item flags
    std::deque<int> queue;                                   // node indices
    std::unordered_map<int, int> done;                       // node -> walk directions done
    std::set<std::pair<int, int>> edges;                     // key ids
    size_t max_nodes; int deaths = 0;
    bool has_cleared = false; Snap cleared_snap; int cleared_parent = -1; Action cleared_act{Action::START};
    double secs = 0;

    Explorer(int st, Game *g, size_t max_nodes = 20000, const Snap *root = nullptr)
        : g(g), st(st), root(root), max_nodes(max_nodes) {
        if (root) g->restore(*root);
        for (int i = 0; i < 128 * 48; i++) if (g->h.mem[0xA000 + i] == 5) gaps.push_back(0xA000 + i);
        int n = g->v(A_NITEMS);
        for (int k = 0; k < n; k++) items.push_back(A_ITEMTAB + k * 9);
        claimed_flag.assign(0x10000, 0);
        open_gaps = gaps; open_items = items;
    }
    int intern(const vector<int> &k) {
        auto it = ids.find(k);
        if (it != ids.end()) return it->second;
        int id = (int)node_of.size(); ids.emplace(k, id); node_of.push_back(-1); return id;
    }
    void note() {
        const uint8_t *m = g->h.mem;
        if (!open_gaps.empty()) {
            bool any = false;
            for (int a : open_gaps) if (m[a] != 5) { claimed_flag[a] = 1; nclaimed++; any = true; }
            if (any) {
                vector<int> keep; for (int a : open_gaps) if (!claimed_flag[a]) keep.push_back(a);
                open_gaps.swap(keep);
            }
        }
        if (!open_items.empty()) {
            bool any = false;
            for (int a : open_items) if (m[a + 8] == 0) { collected.insert(a); any = true; }
            if (any) {
                vector<int> keep; for (int a : open_items) if (!collected.count(a)) keep.push_back(a);
                open_items.swap(keep);
            }
        }
    }
    // returns the node index, or -1
    int add(int parent, Action act, int walked = 0) {
        if (g->v(A_STATION) != st) {
            if (!has_cleared) { has_cleared = true; cleared_snap = g->snap(); cleared_parent = parent; cleared_act = act; }
            return -1;
        }
        int s = g->v(A_BOBSTATE);
        if (s == Game::DYING) { deaths++; return -1; }
        if (s != Game::GROUND && s != Game::CANNON) { note(); return -1; }
        vector<int> k = g->key();
        int id = intern(k);
        if (parent >= 0) edges.insert({key_id_of_node[parent], id});
        note();
        if (node_of[id] >= 0) {
            if (walked) done[node_of[id]] |= walked;
            return node_of[id];
        }
        if (nodes.size() >= max_nodes) return -1;
        int ni = (int)nodes.size();
        nodes.push_back({g->snap(), parent, act});
        key_id_of_node.push_back(id); keys.push_back(k);
        node_of[id] = ni;
        vector<char> f; for (int a : items) f.push_back(g->h.mem[a + 8] != 0);
        items_at.push_back(f);
        if (walked) done[ni] |= walked;
        queue.push_back(ni);
        note();
        return ni;
    }
    vector<int> key_id_of_node;
    vector<vector<int>> keys;

    bool items_here(int ni) {
        const vector<char> &f = items_at[ni];
        for (size_t i = 0; i < items.size(); i++) if (f[i] != (g->h.mem[items[i] + 8] != 0)) return false;
        return true;
    }

    // ---- actions
    void walk(int ni, int d) {
        g->restore(nodes[ni].snap);
        int dbit = d == K_LEFT ? 1 : 2;
        const vector<int> k = keys[ni];          // (a copy: add() grows keys)
        int lastx = g->v(A_BOBX), still = 0;
        for (int i = 0; i < 300; i++) {
            int s = g->frame(KB(d));
            if (s == Game::DYING) { deaths++; return; }
            if (s == Game::GROUND) {
                int x = g->v(A_BOBX);
                if (x == lastx) { if (++still >= 4) break; }
                else {
                    still = 0; lastx = x;
                    vector<int> now = g->key();
                    bool same = vector<int>(now.begin() + std::min<size_t>(3, now.size()), now.end()) ==
                                vector<int>(k.begin() + std::min<size_t>(3, k.size()), k.end()) && items_here(ni);
                    add(ni, {Action::WALK, d}, same ? 3 : 0);
                    (void)dbit;
                }
            } else { g->settle(); add(ni, {Action::WALK, d}); return; }
        }
        note();
    }
    void jump(int ni, int d) {       // d < 0: straight up
        g->restore(nodes[ni].snap);
        uint32_t keys_ = d >= 0 ? KB(d) : 0;
        g->frame(keys_ | KB(K_SPACE));
        for (int i = 0; i < 120; i++) {
            int s = g->frame(keys_);
            if (s == Game::GROUND || s == Game::CANNON || s == Game::DYING || s == Game::SLIDE || s == Game::LADDER) break;
        }
        if (g->v(A_BOBSTATE) == Game::SLIDE) g->settle();
        add(ni, {Action::JUMP, d});
    }
    void climb(int ni, int d) {
        g->restore(nodes[ni].snap);
        if (g->frame(KB(d)) != Game::LADDER) return;
        for (int i = 0; i < 400; i++) if (g->frame(KB(d)) != Game::LADDER) break;
        g->settle(); add(ni, {Action::CLIMB, d});
    }
    void wait(int ni, int n = 20) {
        g->restore(nodes[ni].snap);
        for (int i = 0; i < n; i++) if (g->frame() != Game::GROUND) break;
        g->settle(); add(ni, {Action::WAIT, 0, n});
    }
    void transport(int ni) {
        for (int d = 1; d <= 4; d++) {
            g->restore(nodes[ni].snap);
            for (int i = 0; i < 60; i++) { if (g->v(A_TRLOCK) == 0) break; g->frame(); }
            g->frame(KDIGIT(d)); g->frame(KDIGIT(d));
            if (g->v(A_BOBSTATE) != Game::TRANS) continue;
            g->settle(); add(ni, {Action::TRANS, d});
        }
    }
    void drive(int ni) {
        const int dirs[4][2] = {{K_LEFT, 8}, {K_RIGHT, 8}, {K_UP, 24}, {K_DOWN, 12}};
        for (auto &dn : dirs) {
            g->restore(nodes[ni].snap);
            g->frame(KB(K_ENTER)); g->frame();
            if (!g->v(A_LIFTDRV)) return;
            for (int i = 0; i < dn[1]; i++) g->frame(KB(dn[0]));
            g->frame(); g->frame(KB(K_ENTER)); g->frame();
            g->settle(); add(ni, {Action::DRIVE, dn[0], dn[1]});
        }
    }
    void cannon(int ni) {
        g->restore(nodes[ni].snap); g->frame(KB(K_SPACE));
        g->settle(); add(ni, {Action::FIRE});
        for (int d : {K_LEFT, K_RIGHT}) {
            g->restore(nodes[ni].snap);
            for (int i = 0; i < 8; i++) g->frame(KB(d));
            g->frame(); add(ni, {Action::ROLL, d});
        }
    }

    Explorer &explore() {
        auto t0 = std::chrono::steady_clock::now();
        if (root) g->restore(*root); else g->frame();
        add(-1, {Action::START});
        // waiting is a move wherever something moves on its own: platforms, pulverizers, and
        // live mutants (to let one pass the top of a ladder before climbing into its path)
        bool mutants = false;
        for (int k = 0; k < 8; k++) if (g->h.mem[A_MUTTAB + k * 10 + 7]) mutants = true;
        bool platforms = g->v(A_NPLAT) > 0 || g->v(A_PULVON) || mutants;
        while (!queue.empty()) {
            int ni = queue.front(); queue.pop_front();
            const vector<int> k = keys[ni];
            if (k[2] == Game::CANNON) { cannon(ni); continue; }
            int dn = done.count(ni) ? done[ni] : 0;
            if (!(dn & 1)) walk(ni, K_LEFT);
            if (!(dn & 2)) walk(ni, K_RIGHT);
            jump(ni, K_LEFT); jump(ni, K_RIGHT); jump(ni, -1);
            climb(ni, K_UP); climb(ni, K_DOWN);
            if (platforms) wait(ni);
            if (g->v(A_TRANSON)) transport(ni);
            if (k.size() > 3 && std::find(k.begin(), k.end(), -1000) != k.end()) drive(ni);
        }
        secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        return *this;
    }

    // keys from which Bob can get back to where he started
    std::unordered_set<vector<int>, KeyHash> safe_set() {
        int start = key_id_of_node[0];
        std::unordered_map<int, vector<int>> back;
        for (auto &e : edges) back[e.second].push_back(e.first);
        std::unordered_set<int> safe{start}; vector<int> todo{start};
        while (!todo.empty()) {
            int k = todo.back(); todo.pop_back();
            for (int a : back[k]) if (safe.insert(a).second) todo.push_back(a);
        }
        vector<vector<int>> byid(node_of.size());
        for (auto &kv : ids) byid[kv.second] = kv.first;
        std::unordered_set<vector<int>, KeyHash> out;
        for (int id : safe) out.insert(byid[id]);
        return out;
    }

    vector<std::pair<int, int>> unclaimed() const {
        vector<std::pair<int, int>> out;
        for (int a : gaps) if (!claimed_flag[a]) out.push_back({(a - 0xA000) % 128, (a - 0xA000) / 128});
        std::sort(out.begin(), out.end());
        return out;
    }
    vector<std::array<int, 3>> items_missed() const {
        vector<std::array<int, 3>> out;
        for (int a : items) if (!collected.count(a))
            out.push_back({g->h.mem[a], g->h.mem[a + 1], g->h.mem[a + 5] & 0x7F});
        return out;
    }
    vector<Action> path_to(int ni) const {
        vector<Action> acts;
        while (ni >= 0) { acts.push_back(nodes[ni].act); ni = nodes[ni].parent; }
        std::reverse(acts.begin(), acts.end());
        if (!acts.empty()) acts.erase(acts.begin());
        return acts;
    }
};

// ---- output helpers -------------------------------------------------------------------
static std::mutex out_mx;
static string fmt(const char *f, ...) {
    char b[4096]; va_list ap; va_start(ap, f); vsnprintf(b, sizeof b, f, ap); va_end(ap); return b;
}
static string list_xy(const vector<std::pair<int, int>> &v, size_t maxn = 40) {
    string s = "[";
    for (size_t i = 0; i < v.size() && i < maxn; i++) s += fmt("%s(%d, %d)", i ? ", " : "", v[i].first, v[i].second);
    return s + "]";
}

static string CMD = "../../build/miner3.cmd", LST = "../../build/miner3.lst";

static string explore_station(int st) {
    Game g(st, CMD);
    Explorer e(st, &g);
    e.explore();
    auto un = e.unclaimed(); auto im = e.items_missed();
    string items = "[";
    for (size_t i = 0; i < im.size(); i++) items += fmt("%s(%d, %d, %d)", i ? ", " : "", im[i][0], im[i][1], im[i][2]);
    items += "]";
    return fmt("station %d: %zu nodes, %ld frames in %.1fs; sections %zu, unclaimed %zu %s; items %zu, missed %s; deaths pruned %d",
               st, e.nodes.size(), g.total, e.secs, e.gaps.size(), un.size(), list_xy(un).c_str(), e.items.size(),
               items.c_str(), e.deaths);
}

// ---- the playthrough ------------------------------------------------------------------
struct Player {
    int st; bool verbose; Game *g;
    std::unordered_set<vector<int>, KeyHash> SAFE;
    struct Cand { double score; Snap snap; vector<Action> acts; };

    int sections(const Snap &s) const { return s.station != st ? 0 : s.sections; }

    bool overloaded(const Snap &s) {
        if (st != 10) return false;
        vector<uint8_t> img = g->image(s); const uint8_t *m = img.data() + Game::mem_off();
        vector<int> rows;
        for (auto rt : {std::pair<int, int>{30, 1}, {20, 2}, {10, 3}}) {
            bool any = false;
            for (int x = 0; x < 128; x++) if (m[0xA000 + rt.first * 128 + x] == 5) { any = true; break; }
            if (any) rows.push_back(rt.second);
        }
        if (rows.empty()) return false;
        int carried = m[A_TNT];
        if (carried > 3) return true;
        std::set<int> sums{0};
        for (int k = 0; k < m[A_NITEMS]; k++) {
            int rec = A_ITEMTAB + k * 9;
            if (m[rec + 8] && (m[rec + 5] & 0x7F) >= 34 && (m[rec + 5] & 0x7F) <= 36) {
                std::set<int> add; for (int s2 : sums) add.insert(s2 + m[rec + 4]);
                sums.insert(add.begin(), add.end());
            }
        }
        for (int tons : rows) if (!(carried == tons || sums.count(tons))) return true;
        return false;
    }

    bool viable(const Snap &s, size_t cap = 150) {
        if (overloaded(s)) return false;
        Explorer e(st, g, cap, &s);
        bool fr = g->freeze; g->freeze = true;
        e.explore();
        g->freeze = fr;
        if (e.nodes.size() >= cap) return true;
        if (!e.open_gaps.empty() && verbose) {
            g->restore(s);
            printf("    dead end at (%d, %d, %d) reachable %zu unclaimable from there %zu\n", g->v(A_BOBX), g->v(A_BOBY) + 6,
                   g->v(A_BOBSTATE), e.nodes.size(), e.open_gaps.size());
        }
        return e.open_gaps.empty();
    }

    vector<Cand> candidates(const Snap &root, size_t budget, size_t top = 128, size_t keep = 4) {
        int base = sections(root); int f0 = root.frames;
        for (size_t b = budget; b <= budget * top; b *= 4) {
            Explorer e(st, g, b, &root);
            e.explore();
            if (e.has_cleared) {
                vector<Action> p = e.path_to(e.cleared_parent); p.push_back(e.cleared_act);
                return {{1e9, e.cleared_snap, p}};
            }
            struct C { double sc; int ni; bool safe; };
            vector<C> c;
            for (size_t ni = 0; ni < e.nodes.size(); ni++) {
                const Snap &sn = e.nodes[ni].snap;
                int gain = base - sections(sn);
                if (gain > 0 && !overloaded(sn))
                    c.push_back({gain / (double)std::max(1, sn.frames - f0), (int)ni, true});
            }
            if (!c.empty()) {
                for (auto &x : c) {
                    if (SAFE.empty()) { x.safe = true; continue; }
                    g->restore(e.nodes[x.ni].snap); x.safe = SAFE.count(g->key(false)) > 0;
                }
                std::stable_sort(c.begin(), c.end(), [](const C &a, const C &b) {
                    if (a.safe != b.safe) return a.safe;
                    return a.sc > b.sc;
                });
                vector<Cand> out; std::set<std::array<int, 3>> seen;
                for (auto &x : c) {
                    const Snap &sn = e.nodes[x.ni].snap;
                    std::array<int, 3> sig{sections(sn), sn.bobx, sn.boby};
                    if (seen.insert(sig).second) out.push_back({x.sc, sn, e.path_to(x.ni)});
                    if (out.size() >= keep) break;
                }
                return out;
            }
        }
        return {};
    }

    string play(bool mutants, size_t budget = 100, int max_backtracks = 60, bool frozen = false) {
        auto t0 = std::chrono::steady_clock::now();
        auto elapsed = [&] { return (long)std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count(); };
        {
            Game mg(st, CMD); Explorer ex(st, &mg); ex.explore(); SAFE = ex.safe_set();
        }
        Game game(st, CMD, mutants, frozen ? 1 : 0); g = &game;
        Snap root = g->snap();
        struct Level { Snap state; vector<Cand> choices; vector<Action> acts; size_t b; };
        vector<Level> stack;
        stack.push_back({root, candidates(root, budget), {}, budget});
        int backtracks = 0;
        while (true) {
            Level &L = stack.back();
            if (sections(L.state) == 0) break;
            if (L.choices.empty() && L.b < budget * 1024) {
                L.b *= 4;
                L.choices = candidates(L.state, L.b, 1, 40);
                if (verbose) printf("  wider search (%zu): %zu moves\n", L.b, L.choices.size());
                continue;
            }
            if (L.choices.empty()) {
                Snap state = L.state;
                stack.pop_back(); backtracks++;
                if (stack.empty() || backtracks > max_backtracks) {
                    g->restore(state);
                    vector<uint8_t> img = g->image(state); const uint8_t *m = img.data() + Game::mem_off();
                    vector<std::pair<int, int>> left;
                    for (int a = 0xA000; a < 0xB800 && left.size() < 20; a++)
                        if (m[a] == 5) left.push_back({(a - 0xA000) % 128, (a - 0xA000) / 128});
                    return fmt("{'station': %d, 'cleared': False, 'left': %d, 'gaps': %s, 'backtracks': %d, 'where': (%d, %d, %d), "
                               "'game_seconds': %.1f, 'seconds': %ld}", st, sections(state), list_xy(left).c_str(), backtracks,
                               g->v(A_BOBX), g->v(A_BOBY) + 6, g->v(A_BOBSTATE), state.frames / 30.0, elapsed());
                }
                if (verbose) printf("  back up: sections left %d\n", sections(stack.back().state));
                continue;
            }
            Cand c = L.choices.front(); L.choices.erase(L.choices.begin());
            if (sections(c.snap) && !viable(c.snap)) {
                if (verbose) printf("  skip a move into a dead end\n");
                continue;
            }
            if (verbose) { printf("  sections left %d game time %.1fs\n", sections(c.snap), c.snap.frames / 30.0); fflush(stdout); }
            vector<Action> acts = L.acts; acts.insert(acts.end(), c.acts.begin(), c.acts.end());
            size_t nb = budget;
            vector<Cand> next = sections(c.snap) ? candidates(c.snap, budget) : vector<Cand>{};
            stack.push_back({c.snap, next, acts, nb});
        }
        Level &L = stack.back();
        g->restore(L.state);
        int bonus = g->v(A_BONUS);
        for (int i = 0; i < 400; i++) { g->frame(); if (g->v(A_STATION) != st) break; }
        last_actions = L.acts;
        return fmt("{'station': %d, 'cleared': %s, 'actions': %zu, 'backtracks': %d, 'game_seconds': %.1f, 'bonus_left': '%02X00', "
                   "'next_station': %d, 'seconds': %ld}", st, g->v(A_STATION) != st ? "True" : "False", L.acts.size(), backtracks,
                   L.state.frames / 30.0, bonus, g->v(A_STATION), elapsed());
    }
    vector<Action> last_actions;
};

// ---- check and trace --------------------------------------------------------------------
static uint64_t fnv(const uint8_t *p, size_t n, uint64_t h = 1469598103934665603ull) {
    for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 1099511628211ull; }
    return h;
}
// a fixed key script: the same one tools/trace.py presses
static uint32_t script_keys(int f) {
    static const uint32_t ks[] = {0, KB(K_LEFT), KB(K_RIGHT), KB(K_UP), KB(K_DOWN), KB(K_SPACE),
                                  KB(K_LEFT) | KB(K_SPACE), KB(K_RIGHT) | KB(K_SPACE), KB(K_ENTER)};
    return ks[(f / 17 * 7 + f / 5) % 9];
}
static uint64_t machine_hash(const M3 &h) {
    uint64_t x = fnv(h.mem, 65536);
    uint16_t regs[] = {(uint16_t)h.get_af(), (uint16_t)h.get_bc(), (uint16_t)h.get_de(), (uint16_t)h.get_hl(),
                       (uint16_t)h.get_ix(), (uint16_t)h.get_iy(), (uint16_t)h.get_sp(), (uint16_t)h.get_pc(),
                       (uint16_t)h.get_r()};
    return fnv((const uint8_t *)regs, sizeof regs, x);
}

// ---- main -----------------------------------------------------------------------------
int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: m3test explore|play|check|trace STATION... [-m] [-v] [-f] [-j N] [--no-skip]\n");
        return 2;
    }
    string mode = argv[1];
    vector<int> sts; bool mut = false, verbose = false, frozen = false; int jobs = (int)std::thread::hardware_concurrency();
    int frames_arg = 0, max_bt = 60;
    for (int i = 2; i < argc; i++) {
        string a = argv[i];
        if (a == "-m") mut = true;
        else if (a == "-v") verbose = true;
        else if (a == "-f") frozen = true;
        else if (a == "-j" && i + 1 < argc) jobs = std::max(1, atoi(argv[++i]));
        else if (a.rfind("-j", 0) == 0 && a.size() > 2) jobs = std::max(1, atoi(a.c_str() + 2));
        else if (a == "--no-skip") M3::skip_idle = false;
        else if (a == "--backtracks" && i + 1 < argc) max_bt = atoi(argv[++i]);
        else if (a == "--cmd" && i + 1 < argc) CMD = argv[++i];
        else if (a == "--lst" && i + 1 < argc) LST = argv[++i];
        else if (!a.empty() && isdigit((unsigned char)a[0])) {
            if ((mode == "check" || mode == "trace") && atoi(a.c_str()) > 10) frames_arg = atoi(a.c_str());   // (frames)
            else sts.push_back(atoi(a.c_str()));
        } else { fprintf(stderr, "unknown argument %s\n", a.c_str()); return 2; }
    }
    // paths relative to this program's folder unless given
    {
        string self = argv[0]; size_t p = self.find_last_of('/');
        string dir = p == string::npos ? "." : self.substr(0, p);
        if (CMD.rfind("../", 0) == 0) CMD = dir + "/" + CMD;
        if (LST.rfind("../", 0) == 0) LST = dir + "/" + LST;
    }
    load_syms(LST); bind_syms();
    if (sts.empty()) for (int s = 1; s <= 10; s++) sts.push_back(s);
    if (verbose && mode == "play") jobs = 1;

    if (mode == "trace" || mode == "check") {
        int n = frames_arg ? frames_arg : 3000;
        for (int st : sts) {
            if (mode == "trace") {
                Game g(st, CMD, true, 0);
                for (int f = 0; f < n; f++) { g.frame(script_keys(f)); printf("%d %016llx\n", f, (unsigned long long)machine_hash(g.h)); }
                continue;
            }
            bool keep = M3::skip_idle;
            M3::skip_idle = false; Game a(st, CMD, true, 0);
            M3::skip_idle = true;  Game b(st, CMD, true, 0);
            int bad = -1;
            auto ta = std::chrono::steady_clock::now(); double tA = 0, tB = 0;
            for (int f = 0; f < n && bad < 0; f++) {
                M3::skip_idle = false; auto t1 = std::chrono::steady_clock::now(); a.frame(script_keys(f));
                M3::skip_idle = true;  auto t2 = std::chrono::steady_clock::now(); b.frame(script_keys(f));
                auto t3 = std::chrono::steady_clock::now();
                tA += std::chrono::duration<double>(t2 - t1).count(); tB += std::chrono::duration<double>(t3 - t2).count();
                if (memcmp(a.h.mem, b.h.mem, 65536) || machine_hash(a.h) != machine_hash(b.h)) bad = f;
            }
            (void)ta;
            M3::skip_idle = keep;
            printf("station %d: %s after %d frames; %.0f fps running the idle loop, %.0f fps skipping it\n", st,
                   bad < 0 ? "identical" : fmt("DIFFER at frame %d", bad).c_str(), n, n / tA, n / tB);
            if (bad >= 0) return 1;
        }
        return 0;
    }

    std::function<string(int)> job;
    if (mode == "explore") job = explore_station;
    else if (mode == "play") job = [&](int st) { Player p; p.st = st; p.verbose = verbose; return p.play(mut, 100, max_bt, frozen); };
    else { fprintf(stderr, "unknown mode %s\n", mode.c_str()); return 2; }

    std::atomic<size_t> next{0};
    vector<std::thread> pool;
    for (int t = 0; t < std::min<int>(jobs, (int)sts.size()); t++)
        pool.emplace_back([&] {
            for (size_t i; (i = next++) < sts.size();) {
                string r = job(sts[i]);
                std::lock_guard<std::mutex> lk(out_mx);
                printf("%s\n", r.c_str()); fflush(stdout);
            }
        });
    for (auto &t : pool) t.join();
    return 0;
}
