package io.github.copper.launcher.provider

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.util.Base64
import android.webkit.MimeTypeMap
import io.github.copper.launcher.R
import java.io.File
import java.io.FileNotFoundException
import java.nio.file.Files
import java.util.Locale

/**
 * Copper 的文件提供器：向系统文件选择器（SAF）暴露应用自己的两个 files 目录。
 *
 * 只有一个根：标题 `Copper Launcher`，副标题 `浏览 Copper 的应用文件`。
 * 根下固定两个**虚构文件夹**，名字分别是 `internal` 与 `external`：
 *
 * - `internal` → `/data/data/<包名>/files`（[android.content.Context.getFilesDir]）
 * - `external` → `/sdcard/Android/data/<包名>/files`（[android.content.Context.getExternalFilesDir]）
 *
 * 虚拟根与两个虚拟文件夹只是导航层，真正的文件读写落在两个 files 目录里。
 * token / 配置按**根内相对路径**过滤，不做文件名全盘匹配：
 * 根下的 `mdtbbs_account.json`、`config.json`、`config.bin` 及其锁 / 临时文件、
 * 顶层 `config-backups/` 不会出现在列表里，也不能用构造的 documentId 打开。
 * **`logs/` 不拦截**：日志本来就要随 issue 提供，脱敏在写日志时就完成了（见 `log.dart`）。
 *
 * 安全边界：provider 只声明 `MANAGE_DOCUMENTS`（系统签名权限），普通第三方应用拿不到
 * document URI 就无法访问；逐文件放行由 [isSensitive] 与规范路径校验负责。
 */
class CopperDocumentsProvider : DocumentsProvider() {

    /** storageId（internal / external）→ 真实目录；外部存储不可用时 value 为 null */
    private var storageDirs: Map<String, File?> = emptyMap()

    override fun onCreate(): Boolean {
        val context = context ?: return false
        storageDirs = linkedMapOf(
            STORAGE_INTERNAL to context.filesDir,
            STORAGE_EXTERNAL to context.getExternalFilesDir(null),
        )
        return true
    }

    //region roots / documents

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val cursor = MatrixCursor(projection ?: DEFAULT_ROOT_PROJECTION)
        cursor.putRow(
            Root.COLUMN_ROOT_ID to ROOT_ID,
            Root.COLUMN_DOCUMENT_ID to documentIdOf(DocRef(null, "", null)),
            Root.COLUMN_TITLE to rootTitle(),
            Root.COLUMN_SUMMARY to rootSummary(),
            Root.COLUMN_FLAGS to (Root.FLAG_LOCAL_ONLY or Root.FLAG_SUPPORTS_IS_CHILD),
            Root.COLUMN_MIME_TYPES to "*/*",
            Root.COLUMN_AVAILABLE_BYTES to availableBytes(),
        )
        return cursor
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val ref = decodeOrThrow(documentId)
        // 真实文档必须落盘才返回一行：MT 管理器、DocumentFile.exists() 这类客户端会先 query
        // 一次来判断“这个名字是否已被占用”，对不存在的路径也回一行会被它们当成“文件已存在”。
        // 虚拟根与两个虚拟文件夹始终存在（external 不可用时 file 为 null，但文件夹仍要展示）。
        if (ref.storageId != null && ref.relative.isNotEmpty()) {
            val file = ref.file ?: throw FileNotFoundException(documentId)
            if (!file.exists()) throw FileNotFoundException(documentId)
        }
        val cursor = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        cursor.addDocumentRow(ref)
        return cursor
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val parent = decodeOrThrow(parentDocumentId)
        val cursor = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)

        // 虚拟根：固定返回 internal / external 两个文件夹
        if (parent.storageId == null) {
            for (storageId in STORAGE_IDS) {
                cursor.addDocumentRow(
                    DocRef(storageId, "", storageDirs[storageId])
                )
            }
            return cursor
        }

        // 外部存储不可用：文件夹还在，但里面是空的
        val parentFile = parent.file ?: return cursor
        if (!parentFile.isDirectory) throw FileNotFoundException(parentDocumentId)

        val children = parentFile.listFiles()
            ?.sortedWith(compareBy<File>({ !it.isDirectory }, { it.name.lowercase(Locale.ROOT) }))
            .orEmpty()
        for (child in children) {
            val relative = relativeOf(parent.relative, child.name)
            // 通过 documentId 走一遍 resolve：过滤敏感路径并解开符号链接复查
            val childRef = decode(
                documentIdOf(DocRef(parent.storageId, relative, null))
            ) ?: continue
            cursor.addDocumentRow(childRef)
        }
        return cursor
    }

    /** 系统「文件」里的搜索：桥载荷里有上千个文件，遍历成本不可控，这里只回空结果 */
    override fun querySearchDocuments(
        rootId: String,
        query: String,
        projection: Array<out String>?,
    ): Cursor = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)

    //endregion

    //region open / create / rename / delete

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor {
        val ref = decodeOrThrow(documentId)
        val file = ref.file ?: throw FileNotFoundException(documentId)
        if (file.isDirectory) throw FileNotFoundException(documentId)
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.parseMode(mode))
    }

    override fun createDocument(
        parentDocumentId: String,
        mimeType: String,
        displayName: String,
    ): String {
        val parent = decodeOrThrow(parentDocumentId)
        val parentFile = parent.file ?: throw FileNotFoundException(parentDocumentId)
        if (!parentFile.isDirectory) throw FileNotFoundException(parentDocumentId)

        val name = sanitizeName(displayName) ?: throw IllegalArgumentException("invalid name")
        val relative = relativeOf(parent.relative, name)
        if (isSensitive(relative)) throw IllegalArgumentException("reserved path")

        val target = uniqueChild(parentFile, name)
        val created = if (mimeType == Document.MIME_TYPE_DIR) {
            target.mkdir()
        } else {
            target.createNewFile()
        }
        if (!created) throw FileNotFoundException("cannot create $displayName")
        return documentIdOf(
            DocRef(parent.storageId, relativeOf(parent.relative, target.name), target)
        )
    }

    override fun renameDocument(documentId: String, displayName: String): String {
        val ref = decodeOrThrow(documentId)
        require(ref.storageId != null && ref.relative.isNotEmpty()) {
            "virtual folders cannot be renamed"
        }
        val file = ref.file ?: throw FileNotFoundException(documentId)

        val name = sanitizeName(displayName) ?: throw IllegalArgumentException("invalid name")
        val newRelative = relativeOf(parentOf(ref.relative), name)
        if (isSensitive(newRelative)) throw IllegalArgumentException("reserved path")

        val target = File(file.parentFile, name)
        if (target.exists()) throw IllegalArgumentException("target exists")
        if (!file.renameTo(target)) throw FileNotFoundException("cannot rename $documentId")
        return documentIdOf(DocRef(ref.storageId, newRelative, target))
    }

    override fun deleteDocument(documentId: String) {
        val ref = decodeOrThrow(documentId)
        require(ref.storageId != null && ref.relative.isNotEmpty()) {
            "virtual folders cannot be deleted"
        }
        val file = ref.file ?: throw FileNotFoundException(documentId)
        if (!deleteWithoutFollowingLinks(file)) {
            throw FileNotFoundException("cannot delete $documentId")
        }
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        val parent = decode(parentDocumentId) ?: return false
        val child = decode(documentId) ?: return false

        // 虚拟根包含两个 virtual folder 及其下所有内容
        if (parent.storageId == null) return child.storageId != null
        if (child.storageId != parent.storageId) return false

        val parentFile = parent.file ?: return false
        val childFile = child.file ?: return false
        return childFile.canonicalFile == parentFile.canonicalFile ||
                childFile.canonicalFile.path
                    .startsWith(parentFile.canonicalFile.path + File.separator)
    }

    //endregion

    //region document id / file resolution

    /**
     * 一个已解析的文档。
     *
     * - 虚拟根：[storageId] / [file] 都是 null
     * - internal / external 文件夹本身：[relative] 为空
     * - 外部存储不可用：[file] 为 null，但保留文件夹用于展示
     */
    private data class DocRef(
        val storageId: String?,
        val relative: String,
        /** 根内原始路径；符号链接保留链接本身，删除 / 改名只动链接 */
        val file: File?,
    )

    /**
     * documentId 形如 `copper:<URL_SAFE_BASE64(路径)>`，路径是
     * ``（虚拟根）、`internal` / `external`、或 `internal/子路径` / `external/子路径`。
     */
    private fun documentIdOf(ref: DocRef): String {
        val path = when {
            ref.storageId == null -> ""
            ref.relative.isEmpty() -> ref.storageId
            else -> "${ref.storageId}/${ref.relative}"
        }
        return DOC_ID_PREFIX + encodeRelative(path)
    }

    private fun decode(documentId: String): DocRef? {
        if (!documentId.startsWith(DOC_ID_PREFIX)) return null
        val path = decodeRelative(documentId.substring(DOC_ID_PREFIX.length)) ?: return null

        if (path.isEmpty()) return DocRef(null, "", null)
        val parts = path.split('/', limit = 2)
        val storageId = parts[0]
        if (!storageDirs.containsKey(storageId)) return null
        val relative = if (parts.size == 1) "" else parts[1]
        if (isSensitive(relative)) return null

        val baseDir = storageDirs[storageId]
        if (baseDir == null) {
            // 外部存储不可用：只保留空文件夹本身
            return if (relative.isEmpty()) DocRef(storageId, "", null) else null
        }

        return try {
            val canonicalBase = baseDir.canonicalFile
            val rawFile = if (relative.isEmpty()) {
                canonicalBase
            } else {
                File(canonicalBase, relative)
            }
            // canonicalFile 解开 `..` 与符号链接；不在根内就不认
            val canonicalFile = rawFile.canonicalFile
            if (canonicalFile != canonicalBase &&
                !canonicalFile.path.startsWith(canonicalBase.path + File.separator)
            ) {
                return null
            }
            // 符号链接可能指向根内的敏感路径：按解链后的相对路径再过滤一次
            if (canonicalFile != canonicalBase) {
                val canonicalRelative = canonicalFile.relativeTo(canonicalBase)
                    .invariantSeparatorsPath
                if (isSensitive(canonicalRelative)) return null
            }
            DocRef(storageId, relative, rawFile)
        } catch (_: Exception) {
            null
        }
    }

    private fun decodeOrThrow(documentId: String): DocRef =
        decode(documentId) ?: throw FileNotFoundException(documentId)

    private fun encodeRelative(relative: String): String {
        if (relative.isEmpty()) return ""
        return Base64.encodeToString(
            relative.toByteArray(Charsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )
    }

    private fun decodeRelative(encoded: String): String? = try {
        if (encoded.isEmpty()) {
            ""
        } else {
            val path = String(
                Base64.decode(
                    encoded,
                    Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
                ),
                Charsets.UTF_8,
            )
            // android.util.Base64 的 URL_SAFE 解码器会静默跳过字母表外的字符（'/'、非 ASCII…），
            // 于是「父 id + "/" + 文件名」这种拼接串也能解出一段路径。只认自己编出来的规范串：
            // 重编码对不上就是非法 id，避免伪造 / 拼接的 id 查出并不存在的文档。
            if (encodeRelative(path) == encoded) path else null
        }
    } catch (_: IllegalArgumentException) {
        null
    }

    /**
     * 递归删除目录，但**不跟随符号链接**：桥的原生库目录里就有指向 `bridge/arc/...`
     * 的链接，跟随会把链接目标一起删掉；用户 / 模组创建的外链更不该被波及。
     */
    private fun deleteWithoutFollowingLinks(file: File): Boolean {
        if (Files.isSymbolicLink(file.toPath())) return file.delete()
        if (file.isDirectory) {
            for (child in file.listFiles().orEmpty()) {
                if (!deleteWithoutFollowingLinks(child)) return false
            }
        }
        return file.delete()
    }

    private fun relativeOf(parent: String, name: String): String =
        if (parent.isEmpty()) name else "$parent/$name"

    private fun parentOf(relative: String): String {
        val index = relative.lastIndexOf('/')
        return if (index < 0) "" else relative.substring(0, index)
    }

    //endregion

    //region 过滤与命名

    /**
     * 只按**存储根内的相对路径**判断敏感文件，不做文件名全盘匹配：
     *
     * - 根下的 `mdtbbs_account.json`：refresh token 的固定落盘路径
     * - 根下的 `mdtbbs_account.json.lock` / `mdtbbs_account.json.<pid>.tmp`
     * - 根下的 `config.json` / `config.bin`：GitHub token 与代理密码
     * - 顶层 `config-backups/`：配置旧副本
     *
     * **`logs/` 不在过滤范围**：日志是 issue 的必要材料，脱敏在写入时完成。
     * 嵌套目录里的同名文件（例如某个模组自己的 `config.json`）不算。
     */
    private fun isSensitive(relativePath: String): Boolean {
        val normalized = relativePath.replace('\\', '/').trim('/')
        if (normalized.isEmpty()) return false

        val parts = normalized.split('/')
        val first = parts.first()

        if (parts.size == 1) {
            if (first == ACCOUNT_FILE ||
                first == "config.json" ||
                first == "config.bin" ||
                first == "config-backups"
            ) {
                return true
            }
            // 账号文件同目录的锁 / 临时文件
            return first.startsWith("$ACCOUNT_FILE.") &&
                (first.endsWith(".lock") || first.endsWith(".tmp"))
        }

        // 顶层目录整棵隐藏
        return first == "config-backups"
    }

    /** 显示名只保留文件名语义：路径分隔符与 NUL 换成下划线，"." / ".." 直接拒绝 */
    private fun sanitizeName(raw: String): String? {
        val name = raw.trim()
            .replace('/', '_')
            .replace('\\', '_')
            .replace('\u0000', '_')
        if (name.isEmpty() || name == "." || name == "..") return null
        // 文件名过长在部分文件系统上会直接失败，截到一个安全长度
        return name.take(128)
    }

    /** 同名文件已存在时按 `name (1).ext` 往后找，直到找到空位 */
    private fun uniqueChild(parent: File, name: String): File {
        var candidate = File(parent, name)
        if (!candidate.exists()) return candidate

        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        for (index in 1..MAX_COLLISION_INDEX) {
            candidate = File(parent, "$base ($index)$extension")
            if (!candidate.exists()) return candidate
        }
        throw IllegalStateException("too many files named like $name")
    }

    //endregion

    //region cursor helpers

    private fun MatrixCursor.putRow(vararg values: Pair<String, Any?>) {
        val row = newRow()
        val byName = values.toMap()
        for (column in columnNames) {
            row.add(column, byName[column])
        }
    }

    private fun MatrixCursor.addDocumentRow(ref: DocRef) {
        val file = ref.file
        val isVirtualRoot = ref.storageId == null
        val isStorageRoot = ref.storageId != null && ref.relative.isEmpty()
        val isDirectory = file?.isDirectory ?: true

        val displayName = when {
            isVirtualRoot -> rootTitle()
            isStorageRoot -> ref.storageId ?: ""
            else -> file?.name ?: ref.relative.substringAfterLast('/')
        }
        val summary = when {
            isVirtualRoot -> rootSummary()
            isStorageRoot -> file?.absolutePath ?: unavailableText()
            else -> file?.absolutePath
        }

        val flags = when {
            isVirtualRoot -> 0
            isStorageRoot -> if (file != null) Document.FLAG_DIR_SUPPORTS_CREATE else 0
            isDirectory -> Document.FLAG_DIR_SUPPORTS_CREATE or
                    Document.FLAG_SUPPORTS_RENAME or
                    Document.FLAG_SUPPORTS_DELETE
            else -> Document.FLAG_SUPPORTS_WRITE or
                    Document.FLAG_SUPPORTS_RENAME or
                    Document.FLAG_SUPPORTS_DELETE
        }

        putRow(
            Document.COLUMN_DOCUMENT_ID to documentIdOf(ref),
            Document.COLUMN_DISPLAY_NAME to displayName,
            Document.COLUMN_SUMMARY to summary,
            Document.COLUMN_SIZE to if (isDirectory) 0L else (file?.length() ?: 0L),
            Document.COLUMN_LAST_MODIFIED to (file?.takeIf { it.exists() }?.lastModified() ?: 0L),
            Document.COLUMN_MIME_TYPE to if (isDirectory) {
                Document.MIME_TYPE_DIR
            } else {
                mimeTypeOf(file!!)
            },
            Document.COLUMN_FLAGS to flags,
        )
    }

    private fun mimeTypeOf(file: File): String {
        val extension = file.extension.lowercase(Locale.ROOT)
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }

    private fun rootTitle(): String =
        context?.getString(R.string.documents_root_title) ?: "Copper Launcher"

    private fun rootSummary(): String =
        context?.getString(R.string.documents_root_summary) ?: ""

    private fun unavailableText(): String =
        context?.getString(R.string.documents_storage_unavailable) ?: "unavailable"

    private fun availableBytes(): Long {
        val internal = storageDirs[STORAGE_INTERNAL]?.usableSpace ?: 0L
        val external = storageDirs[STORAGE_EXTERNAL]?.usableSpace ?: 0L
        return internal + external
    }

    //endregion

    private companion object {
        const val ROOT_ID = "copper"
        const val DOC_ID_PREFIX = "copper:"
        const val STORAGE_INTERNAL = "internal"
        const val STORAGE_EXTERNAL = "external"
        val STORAGE_IDS = listOf(STORAGE_INTERNAL, STORAGE_EXTERNAL)
        const val MAX_COLLISION_INDEX = 999

        /** 与 Dart 侧 `AccountStore.fileName` 保持一致；只允许出现在存储根目录 */
        const val ACCOUNT_FILE = "mdtbbs_account.json"

        val DEFAULT_ROOT_PROJECTION = arrayOf(
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_FLAGS,
            Root.COLUMN_MIME_TYPES,
            Root.COLUMN_AVAILABLE_BYTES,
        )

        val DEFAULT_DOCUMENT_PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_SUMMARY,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_FLAGS,
        )
    }
}
