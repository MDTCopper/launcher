import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_client.dart';

/// 把联机 / 好友接口的稳定错误码翻成人话
///
/// 文档口径：**按 `error.code` 判**，服务端的 `message` 只用于展示。码的取值来自
/// 官方错误目录（论坛前端 `errors.*` 那套），认不出的码把服务端的 message 或错误原文
/// 带出去 —— 不自己编一套，也不猜
String describeMdtbbsError(Object error) {
  if (error is! MdtbbsException) return '$error';
  final specific = _cloudSaveDetail(error);
  if (specific != null) return specific;
  final text = _byCode[error.code];
  if (text != null) return text;
  if (error.message.isNotEmpty) return error.message;
  return error.code.isEmpty ? '$error' : error.code;
}

/// 云存档里「哪一份文件 / 哪个字段」这类能说得更准的错误
String? _cloudSaveDetail(MdtbbsException error) {
  switch (error.code) {
    case 'SAVE_FILE_TOO_LARGE':
      final path = error.detailPath;
      return path == null
          ? '有文件超过云端单文件上限（50 MB）'
          : '「$path」超过云端单文件上限（50 MB）';
    case 'SAVE_MANIFEST_LIMIT_EXCEEDED':
      return '文件数量或清单体积超过云端上限';
    case 'SAVE_MANIFEST_INVALID':
      final field = error.detailField;
      return field == null ? '云存档清单格式不对' : '云存档清单格式不对（$field）';
  }
  return null;
}

/// 码 → 提示；文案是启动器的口气（不带句号），与官方目录同义
const Map<String, String> _byCode = {
  // ── 账号与权限 ──
  'AUTH_REQUIRED': '请先登录社区账号',
  'TOKEN_INVALID': '登录状态无效，请到账户页重新登录',
  'TOKEN_EXPIRED': '登录状态已过期，请到账户页重新登录',
  'INSUFFICIENT_SCOPE': '这个应用还没有这项权限',
  'SCOPE_REQUIRED': '这个应用还没有这项权限',
  'PHONE_NOT_VERIFIED': '联机相关操作要先完成手机号验证',
  'EMAIL_VERIFICATION_REQUIRED': '请先验证邮箱',
  'TERMS_ACCEPTANCE_REQUIRED': '请先在社区接受条款',
  'USER_BANNED': '这个账号暂时不能执行该操作',
  'CLIENT_CAPABILITY_NOT_APPROVED': '本启动器还没通过联机客户端能力审核',
  'FEATURE_DISABLED': '社区暂时关闭了这项功能',
  'RATE_LIMITED': '操作太频繁，稍等一下再试',

  // ── 会话 ──
  'SESSION_NOT_FOUND': '房间不存在或已结束',
  'SESSION_EXPIRED': '房间已过期',
  'SESSION_CLOSED': '房间已关闭',
  'SESSION_FULL': '房间人数已满',
  'SESSION_NOT_JOINABLE': '这个房间当前不可加入',
  'SESSION_PERMISSION_DENIED': '你无权访问这个房间',
  'JOIN_REQUEST_REQUIRED': '这个房间要先发加入申请',
  'JOIN_REQUEST_EXPIRED': '加入申请已过期',

  // ── 邀请与加入凭证 ──
  'INVITE_NOT_FOUND': '邀请不存在',
  'INVITE_EXPIRED': '邀请已过期（邀请只有 5 分钟有效）',
  'INVITE_ALREADY_ACCEPTED': '这条邀请已经被接受过了',
  'JOIN_INTENT_INVALID': '加入凭证无效',
  'JOIN_INTENT_CLIENT_MISMATCH': '加入凭证与当前客户端对不上',
  'JOIN_INTENT_EXPIRED': '加入凭证已过期，让对方重新邀请',
  'JOIN_INTENT_CONSUMED': '加入凭证已经被用过了',
  'JOIN_INTENT_RECOVERY_EXPIRED': '加入凭证的恢复窗口已过期',
  'JOIN_INTENT_RECOVERY_UNAVAILABLE': '暂时恢复不了这条加入凭证',

  // ── 对端 ──
  'PEER_NOT_FOUND': '联机对端不存在',
  'PEER_EXPIRED': '联机对端已过期',
  'PEER_RESUME_INVALID': '恢复联机对端失败，请重新加入',

  // ── 中继与候选地址 ──
  'RELAY_UNAVAILABLE': '联机服务器暂时不可用',
  'RELAY_LIMIT_REACHED': '联机服务器还有你的一条旧连接，等 1~2 分钟再试',
  'CANDIDATE_INVALID': '网络候选地址无效',
  'CANDIDATE_LIMIT_REACHED': '网络候选地址数量已达上限',

  // ── 好友与隐私 ──
  'FRIEND_REQUIRED': '需要先成为好友才能联机',
  'USER_BLOCKED': '你们之间有屏蔽关系，没法联机',
  'PRIVACY_DENIED': '对方的隐私设置不允许这个操作',

  // ── 云存档 ──
  'CLOUD_SAVES_DISABLED': '社区暂时关闭了云存档',
  'SAVE_QUOTA_EXCEEDED': '云端空间不够，先删掉一些旧快照再试',
  'SAVE_CONFLICT': '云端存档比本机这份新，先选择怎么处理',
  'SAVE_UPLOAD_ALREADY_COMMITTED': '这次上传其实已经成功，不用重传',
  'SAVE_UPLOAD_NOT_FOUND': '上传会话已过期，重新上传一次',
  'SAVE_BLOB_MISSING': '云端少了几个文件，正在补传',
  'SAVE_UPLOAD_SIZE_MISMATCH': '上传的字节数与清单不符',
  'SAVE_UPLOAD_CHECKSUM_MISMATCH': '上传的内容与清单哈希不符',
  'SAVE_CURRENT_SNAPSHOT_DELETE_FORBIDDEN': '云端当前版本不能删，先传一版新的再删',
  'SAVE_SNAPSHOT_NOT_FOUND': '这份云端快照已经不存在了',
  'IDEMPOTENCY_KEY_REUSED': '同一份请求重复提交了不同内容，请重新上传',
};
