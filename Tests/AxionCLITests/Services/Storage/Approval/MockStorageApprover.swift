import Foundation

import AxionCore
@testable import AxionCLI

/// Mock `StorageApproving`：返回预设响应，并记录收到的请求，供断言门构造的请求是否正确。
final class MockStorageApprover: StorageApproving, @unchecked Sendable {
    let response: StorageApprovalResponse
    private(set) var capturedRequests: [StorageApprovalRequest] = []

    init(response: StorageApprovalResponse) {
        self.response = response
    }

    func collect(request: StorageApprovalRequest, policy: SurfacePolicy) async -> StorageApprovalResponse {
        capturedRequests.append(request)
        return response
    }
}
