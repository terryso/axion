import Foundation
import UniformTypeIdentifiers

/// 底层文件信号归类（基于 UTType / 扩展名派生）。
///
/// **不是最终业务分类** —— Epic 明确：「扩展名、UTType 和文件名模式只作为底层信号，
/// 不是最终分类逻辑」。最终目录分类（如「发票与报销」「项目资料」）由 Agent 基于
/// 信号 + 目录上下文动态生成。`developerCache` 无法从单文件派生，由扫描服务依据
/// 所在目录（`node_modules`/`DerivedData` 等）判定。
public enum FileKind: String, Sendable, Equatable, Codable {
    case installer
    case archive
    case document
    case image
    case video
    case audio
    case developerCache = "developer_cache"
    case other

    /// 由 UTType 标识符与扩展名派生底层信号（纯函数，无 I/O）。
    /// 优先用 `typeIdentifier` 的 UTType conformance；缺失时回退到扩展名映射。
    public static func derive(fileExtension: String?, typeIdentifier: String?) -> FileKind {
        if let id = typeIdentifier?.lowercased() {
            switch id {
            case "public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif":
                return .image
            case "public.mpeg-4", "public.movie", "com.apple.quicktime-movie":
                return .video
            case "public.mp3", "public.audio", "public.mpeg-4-audio":
                return .audio
            case "public.pdf", "public.text", "public.plain-text", "public.rtf":
                return .document
            case "com.apple.application-bundle", "com.apple.package":
                return .installer
            case "public.zip-archive", "org.gnu.gnu-zip-archive", "public.tar-archive":
                return .archive
            default:
                break
            }
        }

        if let id = typeIdentifier, let utt = UTType(id) {
            if utt.conforms(to: .application) { return .installer }
            if utt.conforms(to: .archive) { return .archive }
            if utt.conforms(to: .image) { return .image }
            if utt.conforms(to: .movie) { return .video }
            if utt.conforms(to: .audio) { return .audio }
            if utt.conforms(to: .pdf)
                || utt.conforms(to: .text)
                || utt.conforms(to: .spreadsheet) {
                return .document
            }
        }
        if let ext = fileExtension?.lowercased(), !ext.isEmpty {
            switch ext {
            case "dmg", "pkg", "iso", "deb", "rpm", "msi":
                return .installer
            case "zip", "tar", "gz", "tgz", "rar", "7z", "bz2", "xz", "lz":
                return .archive
            case "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp", "svg":
                return .image
            case "mp4", "mov", "avi", "mkv", "m4v", "webm", "flv", "wmv":
                return .video
            case "mp3", "wav", "aac", "flac", "m4a", "ogg", "opus", "aiff":
                return .audio
            case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md",
                 "csv", "rtf", "pages", "key", "numbers", "odt", "ods", "odp":
                return .document
            default:
                break
            }
        }
        return .other
    }
}
