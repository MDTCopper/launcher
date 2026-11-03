import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_account_api.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_config.dart';
import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_models.dart';
import 'package:copper_launcher/domain/account/account_store.dart';
import 'package:copper_launcher/domain/account/auth_callback_bridge.dart';
import 'package:copper_launcher/domain/account/oauth_loopback_server.dart';
import 'package:copper_launcher/domain/account/pkce.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

/// MDTBBS 账号：登录、保活、退出
///
/// 登录用 Authorization Code + PKCE，**在系统浏览器里完成**（启动器不接触密码）；
/// access token 只在内存，refresh token 落盘。刷新的幂等规则见 [refresh]
/// 账号态的快照：界面订阅它就够，不必自己去问、也不必每次进页面重拉
class AccountSnapshot {
  const AccountSnapshot({
    required this.loggedIn,
    this.username,
    this.avatarUrl,
    this.phoneVerified = false,
    this.hasLanlinkToken = false,
    this.subject,
    this.hasMultiplayerSession = false,
  });

  final bool loggedIn;
  final String? username;

  /// 论坛头像（`/me` 的 `avatar_url`）；没读完资料时为 null
  final String? avatarUrl;

  /// 联机写操作（创建 / 加入房间）要求手机号验证
  final bool phoneVerified;
  final bool hasLanlinkToken;
  final String? subject;

  /// 是否有一份落盘的联机会话（界面可先显示「恢复中」）
  final bool hasMultiplayerSession;
}

class AccountManager {
  AccountManager._();

  static final AccountManager instance = AccountManager._();

  /// 打开系统浏览器；用例可替换掉
  @visibleForTesting
  static Future<bool> Function(Uri url) openBrowser = _launchInBrowser;

  static Future<bool> _launchInBrowser(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  /// 账号态快照；界面订阅它
  final ValueNotifier<AccountSnapshot> snapshot = ValueNotifier(
    const AccountSnapshot(loggedIn: false),
  );

  StoredAccount? _storedField;
  MdtbbsAccount? _accountField;

  /// 读写都走这两个漏斗：任何一处赋值都会广播一次快照，
  /// 省得在每个改账号态的方法里各写一遍通知（漏一处界面就不同步）
  StoredAccount? get _stored => _storedField;
  set _stored(StoredAccount? value) {
    _storedField = value;
    _publish();
  }

  MdtbbsAccount? get _account => _accountField;
  set _account(MdtbbsAccount? value) {
    _accountField = value;
    _publish();
  }

  void _publish() {
    final stored = _storedField;
    final account = _accountField;
    snapshot.value = AccountSnapshot(
      loggedIn: stored?.isLoggedIn ?? false,
      username: account?.username ?? stored?.username,
      avatarUrl: account?.avatar,
      phoneVerified: account?.phoneVerified ?? false,
      hasLanlinkToken: stored?.hasLanlinkToken ?? false,
      subject: stored?.subject,
      hasMultiplayerSession: stored?.multiplayerSession != null,
    );
  }

  String? _accessToken;
  DateTime? _accessTokenExpiresAt;

  /// 账号态每次被「清掉 / 换人」就加一：异步操作回来后先比 epoch，
  /// 不一致就丢弃结果（否则退出登录瞬间到达的刷新结果会把 token 写回、甚至串号）
  int _epoch = 0;

  /// 正在进行的刷新；并发调用共用一次请求，别一起放大失败
  Future<bool>? _refreshing;

  /// 账号文件最后被本进程看到的时间；用来发现「另一个进程改过 / 登出了」
  DateTime? _diskStamp;

  /// 是不是配了 client_id；没配就别显示登录入口
  bool get isConfigured => MdtbbsConfig.isConfigured;

  bool get isLoggedIn => _stored?.isLoggedIn ?? false;

  MdtbbsAccount? get account => _account;

  String? get subject => _stored?.subject;

  /// 联机服务（LanLink 控制面）的令牌
  ///
  /// 它与 BBS 是同一个论坛账号，所以不另开一份登录态：存进同一份账号文件，
  /// 退出 BBS 时整份被清掉，联机令牌跟着失效
  String? get lanlinkToken => _stored?.lanlinkToken;

  bool get hasLanlinkToken => _stored?.hasLanlinkToken ?? false;

  /// 记下联机服务令牌；**没有 BBS 账号态时直接忽略**
  ///
  /// 联机账号是附属在社区账号上的，没有账号就不该单独存在一份联机登录
  void saveLanlinkToken(String token) {
    final stored = _stored;
    if (stored == null || token.isEmpty) return;
    _stored = stored.copyWith(lanlinkToken: token);
    AccountStore.save(_stored!);
  }

  /// 联机会话（官方 multiplayer）：加入码只在创建响应里给一次，必须落盘
  StoredMultiplayerSession? get multiplayerSession =>
      _stored?.multiplayerSession;

  void saveMultiplayerSession(StoredMultiplayerSession session) {
    final stored = _stored;
    if (stored == null) return;
    _stored = stored.copyWith(
      multiplayerSession: session.copyWith(savedAt: DateTime.now()),
    );
    AccountStore.save(_stored!);
  }

  void clearMultiplayerSession() {
    final stored = _stored;
    if (stored == null || stored.multiplayerSession == null) return;
    _stored = stored.copyWith(clearMultiplayerSession: true);
    AccountStore.save(_stored!);
  }

  void clearLanlinkToken() {
    final stored = _stored;
    if (stored == null) return;
    _stored = stored.copyWith(clearLanlinkToken: true);
    AccountStore.save(_stored!);
  }

  /// 这一次运行有没有读过盘
  ///
  /// 页面进来时该用 [ensureRestored]：`restore()` 会清内存（连 access token 一起），
  /// 每次都读一遍就会逼着下一次 `ensureAccessToken()` 重新刷新 —— 反复进页面每次都要等
  bool _restored = false;

  /// 启动时读一次盘：client_id 换过就当作未登录（那份 token 属于别的应用）
  ///
  /// 先清内存再读：否则「盘上没有账号态」或「client_id 不符」时，
  /// 上一轮留在内存里的登录态会继续被当成有效
  Future<void> restore() async {
    _clearMemory();
    _restored = true;

    final stored = AccountStore.load();
    _diskStamp = AccountStore.lastModified();
    if (stored == null) return;
    if (!MdtbbsConfig.isConfigured ||
        !stored.matchesClient(MdtbbsConfig.clientId)) {
      addLogAndPrint(.info, '账号态的 client_id 与当前配置不符，按未登录处理', tag: 'Account');
      AccountStore.clear();
      return;
    }
    _stored = stored;
  }

  /// 页面进来时用这个：这次运行已经读过盘就直接返回，不再清内存、不再丢 access token
  Future<void> ensureRestored() async {
    if (_restored) return;
    await restore();
  }

  /// 走完一整条登录：起本地回调 → 开系统浏览器 → 换 token → 读账号
  ///
  /// [onAuthorizeUrl] 给 UI 一个「打不开浏览器时手动复制」的机会
  Future<MdtbbsAccount> login({
    void Function(String url)? onAuthorizeUrl,
    CancelToken? cancelToken,
  }) async {
    if (!isConfigured) {
      throw const MdtbbsException(message: '还没配置 MDTBBS client_id，无法登录');
    }
    final epoch = _epoch;

    // 每次登录都重新生成，绝不复用上一次留下的 PKCE 值
    final verifier = Pkce.createVerifier();
    final challenge = Pkce.challengeOf(verifier);
    final state = Pkce.createState();

    // 走「URL 回到软件」时不需要本地回调服务器：浏览器授权完由系统唤起启动器
    // （需要 MindAuth 那边把 copperlauncher://oauth/callback 登记为回调地址）
    final useScheme = MdtbbsConfig.useSchemeRedirect;
    OAuthLoopbackServer? loopback;
    final String redirectUri;
    if (useScheme) {
      redirectUri = MdtbbsConfig.schemeRedirectUri;
    } else {
      loopback = await OAuthLoopbackServer.start(expectedState: state);
      redirectUri = loopback.redirectUri;
    }
    final authorizeUrl = MdtbbsAccountApi.authorizeUrl(
      redirectUri: redirectUri,
      state: state,
      codeChallenge: challenge,
    );
    onAuthorizeUrl?.call(authorizeUrl);
    addLogAndPrint(
      .info,
      useScheme ? '开始登录 BBS，等待 URL 回调' : '开始登录 BBS，回调端口 ${loopback!.port}',
      tag: 'Account',
    );

    try {
      if (!await openBrowser(Uri.parse(authorizeUrl))) {
        addLogAndPrint(.warning, '打开系统浏览器失败', tag: 'Account');
        throw const MdtbbsException(message: '没能打开系统浏览器');
      }
      addLogAndPrint(.info, '已在系统浏览器打开授权页，等待回调', tag: 'Account');

      final OAuthCallbackResult result;
      if (useScheme) {
        final uri = await AuthCallbackBridge.wait(
          timeout: const Duration(minutes: 3),
          accept: (uri) =>
              uri.scheme == 'copperlauncher' && uri.queryParameters['state'] == state,
        );
        result = uri == null
            ? const OAuthCallbackResult(error: 'timeout', errorDescription: '没等到回调')
            : OAuthCallbackResult(
                code: uri.queryParameters['code'],
                error: uri.queryParameters['error'],
                errorDescription: uri.queryParameters['error_description'],
              );
      } else {
        result = await loopback!.waitForCallback();
      }
      if (!result.isSuccess) {
        addLogAndPrint(
          .warning,
          '授权回调未成功：${result.error ?? 'unknown'}',
          tag: 'Account',
        );
        throw MdtbbsException(
          code: result.error ?? 'authorize_failed',
          message: result.errorDescription ?? '授权未完成',
        );
      }

      final tokens = await MdtbbsAccountApi.exchangeCode(
        code: result.code!,
        codeVerifier: verifier,
        redirectUri: redirectUri,
        cancelToken: cancelToken,
      );
      // 等的时候用户退出 / 又点了别的登录：这次结果作废
      if (epoch != _epoch) {
        throw const MdtbbsException(message: '登录已被取消');
      }
      final refresh = tokens.refreshToken;
      if (refresh == null || refresh.isEmpty) {
        throw const MdtbbsException(message: '服务端没给 refresh token，登录失败');
      }
      _acceptTokens(tokens);
      _stored = StoredAccount(
        clientId: MdtbbsConfig.clientId,
        refreshToken: refresh,
      );
      if (!AccountStore.save(_stored!)) {
        throw const MdtbbsException(message: '登录凭证没写进盘，请检查磁盘权限后重试');
      }
      _restored = true;
      _diskStamp = AccountStore.lastModified();

      // 资料读不回来不算登录失败：token 已经落地，状态是「已登录、资料待刷新」
      try {
        return await loadAccount(cancelToken: cancelToken, force: true);
      } on Object catch (error) {
        addLogAndPrint(
          .warning,
          '已登录，但资料没读回来（稍后可重试）：${removeNewlines('$error')}',
          tag: 'Account',
        );
        return MdtbbsAccount(subject: _stored?.subject ?? '');
      }
    } finally {
      await loopback?.close();
    }
  }

  /// 读当前账号资料（顺带把 subject / username 补进账号态）
  ///
  /// 内存里已经有一份就直接返回，不再打 `/me` —— 进页面不该每次等一次网络；
  /// 要强制刷新资料传 [force]（登录后那一趟本来就会走网络）
  Future<MdtbbsAccount> loadAccount({
    CancelToken? cancelToken,
    bool force = false,
  }) async {
    final epoch = _epoch;
    final cached = _account;
    if (cached != null && !force) return cached;
    final token = await ensureAccessToken(cancelToken: cancelToken);
    if (token == null) {
      throw const MdtbbsException(message: '未登录');
    }
    final account = await MdtbbsAccountApi.me(
      accessToken: token,
      cancelToken: cancelToken,
    );
    // 等 /me 的时候退出 / 换号了：别把旧账号的资料写成新账号的
    if (epoch != _epoch) {
      throw const MdtbbsException(message: '账号已切换，这次资料作废');
    }
    _account = account;
    addLog(
      .debug,
      '账号资料：${account.username ?? '?'} 头像=${account.avatar ?? '无'}',
      tag: 'Account',
    );
    final stored = _stored;
    if (stored != null) {
      _stored = stored.copyWith(
        subject: account.subject,
        username: account.username,
      );
      AccountStore.save(_stored!);
    }
    return account;
  }

  /// 拿一个可用的 access token；过期内或没有就刷新一次
  ///
  /// 刷新失败（网络 / 5xx）时返回 null，**不交出过期的那一份**：
  /// 调用方只看「非 null 即成功」，交旧的只会换来一串 401
  Future<String?> ensureAccessToken({CancelToken? cancelToken}) async {
    await _syncFromDiskIfChanged();
    if (_accessToken != null && !_isAccessTokenExpired()) return _accessToken;
    if (!isLoggedIn) return null;
    final ok = await refresh(cancelToken: cancelToken);
    if (!ok) return null;
    return _accessToken;
  }

  /// 另一个进程改过账号文件时就按盘上的来（登出 / 换号 / 轮换了 token）
  ///
  /// 账号文件没有跨进程锁，两个进程各自只读一次盘；不比对的话，
  /// 一边轮换完另一边还在用旧 refresh token，刷新会 invalid_grant 把对方登出
  Future<void> _syncFromDiskIfChanged() async {
    if (!_restored) return;
    final stamp = AccountStore.lastModified();
    if (stamp == null) {
      // 盘上没有账号态了：另一个进程登出 / 换号
      if (_stored != null) {
        addLogAndPrint(.info, '账号态已被另一个进程清掉，按未登录处理', tag: 'Account');
        _forget(persist: false);
      }
      return;
    }
    final seen = _diskStamp;
    if (seen != null && !stamp.isAfter(seen)) return;
    final disk = AccountStore.load();
    _diskStamp = stamp;
    if (disk == null) {
      _forget(persist: false);
      return;
    }
    _stored = disk;
  }

  /// 刷新 token，按官方那套幂等规则来
  ///
  /// - 发请求**之前**先把「本次尝试」的幂等键与所用 refresh token 落盘；
  /// - 上一次尝试还在 10 分钟窗口内且没成功 → 用**原 token + 同一个 key** 重试；
  /// - 成功才原子覆盖新的 refresh token 并清掉未决尝试；
  /// - `invalid_grant` 说明这份 refresh token 已经废了（被轮换掉或授权被撤销），
  ///   重试没有意义 ⇒ 直接按未登录处理
  Future<bool> refresh({CancelToken? cancelToken}) {
    final running = _refreshing;
    if (running != null) return running;
    final future = _refreshOnce(cancelToken);
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<bool> _refreshOnce(CancelToken? cancelToken) async {
    final stored = _stored;
    if (stored == null || !stored.isLoggedIn) return false;
    final epoch = _epoch;
    _diskStamp = AccountStore.lastModified();

    final now = DateTime.now();
    final reusePending =
        stored.hasPendingRefresh && stored.isPendingRefreshFresh(now);
    final idempotencyKey = reusePending
        ? stored.pendingRefreshKey!
        : const Uuid().v4();
    final refreshToken = reusePending
        ? stored.pendingRefreshToken!
        : stored.refreshToken!;

    _stored = stored.copyWith(
      pendingRefreshKey: idempotencyKey,
      pendingRefreshToken: refreshToken,
      pendingRefreshAt: now,
    );
    // 幂等键没落盘就别发请求：超时后重试会变成「新 key + 旧 token」，
    // 服务端可能按重放处理，撤掉这个账号在该客户端的全部 refresh token
    if (!AccountStore.save(_stored!)) {
      addLogAndPrint(
        .warning,
        '幂等键没写进盘，这次不刷新（避免重放）：稍后重试',
        tag: 'Account',
      );
      return false;
    }

    final MdtbbsTokens tokens;
    try {
      tokens = await MdtbbsAccountApi.refresh(
        refreshToken: refreshToken,
        idempotencyKey: idempotencyKey,
        cancelToken: cancelToken,
      );
    } on MdtbbsException catch (error) {
      if (epoch != _epoch) return false;
      if (error.code == 'invalid_grant') {
        // 盘上可能已经被另一个进程换成新 token 了：只有这份还是自己那份才登出
        final disk = AccountStore.load();
        if (disk != null &&
            disk.refreshToken != null &&
            disk.refreshToken != refreshToken &&
            disk.isLoggedIn) {
          addLogAndPrint(
            .info,
            '账号态已被另一个进程刷新，采用盘上的凭证',
            tag: 'Account',
          );
          _stored = disk;
          _accessToken = null;
          _accessTokenExpiresAt = null;
          return refresh(cancelToken: cancelToken);
        }
        addLogAndPrint(.warning, '登录已失效，需要重新登录', tag: 'Account');
        _forget();
        return false;
      }
      // 超时 / 5xx 时结果未知：留着未决尝试，10 分钟内用同一个 key 重试
      addLogAndPrint(
        .warning,
        '刷新登录凭证失败，稍后可用同一幂等键重试：${removeNewlines('$error')}',
        tag: 'Account',
      );
      return false;
    }

    // 刷新期间退出 / 换号了：结果作废，不写回
    if (epoch != _epoch || _stored == null) return false;

    _acceptTokens(tokens);
    _stored = _stored!.copyWith(
      refreshToken: tokens.refreshToken ?? refreshToken,
      clearPendingRefresh: true,
    );
    if (!AccountStore.save(_stored!)) {
      // 服务端已经轮换、盘上还是旧的：重启就得重登，不如现在就说清
      addLogAndPrint(
        .warning,
        '新的登录凭证没写进盘，下次启动可能需要重新登录',
        tag: 'Account',
      );
    }
    _diskStamp = AccountStore.lastModified();
    return true;
  }

  /// 退出登录：先按官方要求撤销 token，再清本地
  ///
  /// 撤销失败不拦住退出（本地凭证该清还是要清）
  Future<void> logout({CancelToken? cancelToken}) async {
    final token = _stored?.refreshToken ?? _stored?.pendingRefreshToken;
    final epoch = _epoch;
    if (token != null && token.isNotEmpty && isConfigured) {
      try {
        await MdtbbsAccountApi.revoke(token: token, cancelToken: cancelToken);
      } catch (error) {
        addLogAndPrint(
          .warning,
          '撤销登录凭证失败，仍按退出处理：${removeNewlines('$error')}',
          tag: 'Account',
        );
      }
    }
    // 撤销期间又登录了别的账号：别把新登录清掉
    if (epoch != _epoch) return;
    _forget();
  }

  void _acceptTokens(MdtbbsTokens tokens) {
    final access = tokens.accessToken;
    if (access.isEmpty) {
      throw const MdtbbsException(message: '服务端没给 access token');
    }
    _accessToken = access;
    // 提前一分钟认定过期，别卡在边界上；`expires_in` 缺失就给个保守值，
    // 否则「永不过期」= 永不刷新，只能等 401（而这条链路没有 401 自愈）
    final expiresIn = tokens.expiresIn ?? 300;
    final effective = expiresIn - 60;
    _accessTokenExpiresAt = DateTime.now().add(
      Duration(seconds: effective < 30 ? 30 : effective),
    );
  }

  bool _isAccessTokenExpired() {
    final at = _accessTokenExpiresAt;
    if (at == null) return false;
    return !DateTime.now().isBefore(at);
  }

  /// 清本地登录态（可选连盘）：[persist] false 用于「盘上已经被别人清掉」
  void _forget({bool persist = true}) {
    _clearMemory();
    if (persist) AccountStore.clear();
  }

  /// 只清内存：退出登录要连盘一起清（[_forget]），重新读盘前则只清内存
  void _clearMemory() {
    _epoch++;
    _stored = null;
    _accessToken = null;
    _accessTokenExpiresAt = null;
    _account = null;
    _diskStamp = null;
  }
}
