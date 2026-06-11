import Foundation

/// 单文件提取的信号。工具/入口/远程面向契约，使用显式 snake_case `CodingKeys`
/// （区别于 config 的 camelCase 默认）。日期以 ISO8601 字符串保存（与
/// `axionSortedEncoder` 无日期策略保持一致）。
public struct FileSignal: Codable, Equatable, Sendable {

    /// 绝对路径。
    public var path: String
    /// 文件名（含扩展名）。
    public var name: String
    /// 文件扩展名（不含点，小写）。
    public var fileExtension: String?
    /// UTType 标识符（`typeIdentifier`）。
    public var uti: String?
    /// 字节大小。
    public var sizeBytes: Int64
    /// 创建时间（ISO8601 字符串）。
    public var createdAt: String?
    /// 修改时间（ISO8601 字符串）。
    public var modifiedAt: String?
    /// 是否为目录。
    public var isDirectory: Bool
    /// 是否为 bundle/package。
    public var isBundle: Bool
    /// 是否隐藏。
    public var isHidden: Bool
    /// 是否为符号链接（仅记录路径项，不跟随目标）。
    public var isSymbolicLink: Bool
    /// 是否落在 `~/Downloads` 下。
    public var isFromDownloads: Bool
    /// 底层信号分类。
    public var kind: FileKind

    enum CodingKeys: String, CodingKey {
        case path, name
        case fileExtension = "file_extension"
        case uti
        case sizeBytes = "size_bytes"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case isDirectory = "is_directory"
        case isBundle = "is_bundle"
        case isHidden = "is_hidden"
        case isSymbolicLink = "is_symbolic_link"
        case isFromDownloads = "is_from_downloads"
        case kind
    }

    public init(
        path: String,
        name: String,
        fileExtension: String? = nil,
        uti: String? = nil,
        sizeBytes: Int64 = 0,
        createdAt: String? = nil,
        modifiedAt: String? = nil,
        isDirectory: Bool = false,
        isBundle: Bool = false,
        isHidden: Bool = false,
        isSymbolicLink: Bool = false,
        isFromDownloads: Bool = false,
        kind: FileKind = .other
    ) {
        self.path = path
        self.name = name
        self.fileExtension = fileExtension
        self.uti = uti
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.isBundle = isBundle
        self.isHidden = isHidden
        self.isSymbolicLink = isSymbolicLink
        self.isFromDownloads = isFromDownloads
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? (path as NSString).lastPathComponent
        fileExtension = try c.decodeIfPresent(String.self, forKey: .fileExtension)
        uti = try c.decodeIfPresent(String.self, forKey: .uti)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        modifiedAt = try c.decodeIfPresent(String.self, forKey: .modifiedAt)
        isDirectory = try c.decodeIfPresent(Bool.self, forKey: .isDirectory) ?? false
        isBundle = try c.decodeIfPresent(Bool.self, forKey: .isBundle) ?? false
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isSymbolicLink = try c.decodeIfPresent(Bool.self, forKey: .isSymbolicLink) ?? false
        isFromDownloads = try c.decodeIfPresent(Bool.self, forKey: .isFromDownloads) ?? false
        kind = try c.decodeIfPresent(FileKind.self, forKey: .kind) ?? .other
    }
}
