#include "file_drag_out.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>

#include <array>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace {

// CF_HDROP 的载荷 = 一个 DROPFILES 头 + 以双 NUL 收尾的宽字符路径表
std::vector<BYTE> BuildDropFiles(const std::vector<std::wstring>& paths) {
  size_t bytes = sizeof(DROPFILES);
  for (const std::wstring& path : paths) {
    bytes += (path.size() + 1) * sizeof(wchar_t);
  }
  bytes += sizeof(wchar_t);

  std::vector<BYTE> buffer(bytes);
  DROPFILES* header = reinterpret_cast<DROPFILES*>(buffer.data());
  header->pFiles = sizeof(DROPFILES);
  header->fWide = TRUE;

  wchar_t* cursor = reinterpret_cast<wchar_t*>(buffer.data() + sizeof(DROPFILES));
  for (const std::wstring& path : paths) {
    std::memcpy(cursor, path.c_str(), (path.size() + 1) * sizeof(wchar_t));
    cursor += path.size() + 1;
  }
  *cursor = L'\0';
  return buffer;
}

// 有些接收方（聊天窗口之类）只吃文本，顺手给一份换行分隔的路径
std::wstring JoinPaths(const std::vector<std::wstring>& paths) {
  std::wstring text;
  for (size_t index = 0; index < paths.size(); ++index) {
    if (index != 0) {
      text += L"\r\n";
    }
    text += paths[index];
  }
  return text;
}

// 只够拖出用的 IDataObject：对外给 CF_HDROP 与 CF_UNICODETEXT 两种格式
//
// 引用计数归零时自己删掉；DoDragDrop 返回后由调用方 Release
class FileDropDataObject : public IDataObject {
 public:
  explicit FileDropDataObject(std::vector<std::wstring> paths)
      : paths_(std::move(paths)),
        drop_files_(BuildDropFiles(paths_)),
        text_(JoinPaths(paths_)) {
    for (FORMATETC& format : formats_) {
      format.ptd = nullptr;
      format.dwAspect = DVASPECT_CONTENT;
      format.lindex = -1;
      format.tymed = TYMED_HGLOBAL;
    }
    formats_[0].cfFormat = CF_HDROP;
    formats_[1].cfFormat = CF_UNICODETEXT;
  }

  // IUnknown
  HRESULT __stdcall QueryInterface(REFIID iid, void** object) override {
    if (object == nullptr) {
      return E_POINTER;
    }
    if (IsEqualIID(iid, __uuidof(IDataObject)) ||
        IsEqualIID(iid, __uuidof(IUnknown))) {
      *object = static_cast<IDataObject*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  ULONG __stdcall AddRef() override {
    return static_cast<ULONG>(InterlockedIncrement(&ref_count_));
  }

  ULONG __stdcall Release() override {
    const LONG count = InterlockedDecrement(&ref_count_);
    if (count == 0) {
      delete this;
    }
    return static_cast<ULONG>(count);
  }

  // IDataObject
  HRESULT __stdcall GetData(FORMATETC* format, STGMEDIUM* medium) override {
    if (format == nullptr || medium == nullptr) {
      return E_POINTER;
    }
    const BYTE* source = nullptr;
    size_t bytes = 0;
    if (format->cfFormat == CF_HDROP) {
      source = drop_files_.data();
      bytes = drop_files_.size();
    } else if (format->cfFormat == CF_UNICODETEXT) {
      source = reinterpret_cast<const BYTE*>(text_.c_str());
      bytes = (text_.size() + 1) * sizeof(wchar_t);
    } else {
      return DV_E_FORMATETC;
    }
    if ((format->tymed & TYMED_HGLOBAL) == 0 || format->lindex != -1 ||
        format->dwAspect != DVASPECT_CONTENT) {
      return DV_E_FORMATETC;
    }

    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (memory == nullptr) {
      return STG_E_MEDIUMFULL;
    }
    void* target = GlobalLock(memory);
    if (target == nullptr) {
      GlobalFree(memory);
      return STG_E_MEDIUMFULL;
    }
    std::memcpy(target, source, bytes);
    GlobalUnlock(memory);

    medium->tymed = TYMED_HGLOBAL;
    medium->hGlobal = memory;
    medium->pUnkForRelease = nullptr;
    return S_OK;
  }

  HRESULT __stdcall GetDataHere(FORMATETC*, STGMEDIUM*) override {
    return E_NOTIMPL;
  }

  HRESULT __stdcall QueryGetData(FORMATETC* format) override {
    if (format == nullptr) {
      return E_POINTER;
    }
    if (format->cfFormat != CF_HDROP && format->cfFormat != CF_UNICODETEXT) {
      return DV_E_FORMATETC;
    }
    if ((format->tymed & TYMED_HGLOBAL) == 0) {
      return DV_E_TYMED;
    }
    if (format->lindex != -1) {
      return DV_E_LINDEX;
    }
    if (format->dwAspect != DVASPECT_CONTENT) {
      return DV_E_DVASPECT;
    }
    return S_OK;
  }

  HRESULT __stdcall GetCanonicalFormatEtc(FORMATETC*, FORMATETC* out) override {
    if (out != nullptr) {
      out->ptd = nullptr;
    }
    return E_NOTIMPL;
  }

  HRESULT __stdcall SetData(FORMATETC*, STGMEDIUM*, BOOL) override {
    return E_NOTIMPL;
  }

  HRESULT __stdcall EnumFormatEtc(DWORD direction,
                                  IEnumFORMATETC** enumerator) override {
    if (direction != DATADIR_GET || enumerator == nullptr) {
      return E_NOTIMPL;
    }
    return SHCreateStdEnumFmtEtc(static_cast<UINT>(formats_.size()),
                                 formats_.data(), enumerator);
  }

  HRESULT __stdcall DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }

  HRESULT __stdcall DUnadvise(DWORD) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }

  HRESULT __stdcall EnumDAdvise(IEnumSTATDATA**) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }

 private:
  ~FileDropDataObject() = default;

  LONG ref_count_ = 1;
  std::vector<std::wstring> paths_;
  std::vector<BYTE> drop_files_;
  std::wstring text_;
  std::array<FORMATETC, 2> formats_ = {};
};

// Flutter 给的路径是 UTF-8 的窄字符
std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      wide.data(), length);
  return wide;
}

// 从窗口客户区里的逻辑像素换到屏幕上的物理像素
POINT ToScreenPoint(HWND window, POINT logical_point, double scale_factor) {
  POINT screen = {static_cast<LONG>(logical_point.x * scale_factor),
                  static_cast<LONG>(logical_point.y * scale_factor)};
  ClientToScreen(window, &screen);
  return screen;
}

// 开始一次文件拖出，返回是否真的落到了别处
//
// 会一直阻塞到拖放结束：DoDragDrop 自己跑消息循环，拖拽期间界面不刷新是正常的
// （资源管理器从自己窗口里拖文件也是这样）
bool StartFileDragOut(HWND window, const std::vector<std::wstring>& paths,
                      POINT logical_point, double scale_factor) {
  // 拖放要求 STA —— 主线程在 main.cpp 里已经 CoInitializeEx 成 STA 了，
  // 这里再补一次 OLE 的那部分（重复初始化返回 S_FALSE，也算成功）
  static const HRESULT ole_result = OleInitialize(nullptr);
  if (FAILED(ole_result)) {
    return false;
  }

  FileDropDataObject* data = new FileDropDataObject(paths);
  const POINT screen = ToScreenPoint(window, logical_point, scale_factor);
  DWORD effect = DROPEFFECT_NONE;
  const HRESULT result = DoDragDrop(data, nullptr, DROPEFFECT_COPY, &effect);
  data->Release();
  return SUCCEEDED(result) && effect != DROPEFFECT_NONE;
}

// 取 map 里的路径表；认不出就当空表
std::vector<std::wstring> ReadPaths(const flutter::EncodableMap& arguments) {
  std::vector<std::wstring> paths;
  const auto entry = arguments.find(flutter::EncodableValue("paths"));
  if (entry == arguments.end()) {
    return paths;
  }
  const flutter::EncodableList* list =
      std::get_if<flutter::EncodableList>(&entry->second);
  if (list == nullptr) {
    return paths;
  }
  for (const flutter::EncodableValue& item : *list) {
    const std::string* path = std::get_if<std::string>(&item);
    if (path != nullptr && !path->empty()) {
      paths.push_back(Utf8ToWide(*path));
    }
  }
  return paths;
}

double ReadDouble(const flutter::EncodableMap& arguments, const char* key,
                  double fallback) {
  const auto entry = arguments.find(flutter::EncodableValue(key));
  if (entry == arguments.end()) {
    return fallback;
  }
  if (const double* value = std::get_if<double>(&entry->second)) {
    return *value;
  }
  if (const int32_t* value = std::get_if<int32_t>(&entry->second)) {
    return static_cast<double>(*value);
  }
  if (const int64_t* value = std::get_if<int64_t>(&entry->second)) {
    return static_cast<double>(*value);
  }
  return fallback;
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateFileDragOutChannel(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "io.github.copper.launcher/dragout",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [window](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                   result) {
        if (call.method_name() != "startDrag") {
          result->NotImplemented();
          return;
        }
        const flutter::EncodableMap* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("bad_arguments", "startDrag expects a map");
          return;
        }
        const std::vector<std::wstring> paths = ReadPaths(*arguments);
        if (paths.empty()) {
          result->Success(flutter::EncodableValue(false));
          return;
        }
        const POINT point = {
            static_cast<LONG>(ReadDouble(*arguments, "x", 0)),
            static_cast<LONG>(ReadDouble(*arguments, "y", 0))};
        const double scale_factor = ReadDouble(*arguments, "dpr", 1);
        result->Success(flutter::EncodableValue(
            StartFileDragOut(window, paths, point, scale_factor)));
      });

  return channel;
}
