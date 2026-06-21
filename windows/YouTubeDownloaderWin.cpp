#include <windows.h>
#include <commctrl.h>
#include <shlobj.h>
#include <shellapi.h>

#include <algorithm>
#include <cwctype>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

constexpr int IDC_LINKS = 1001;
constexpr int IDC_MP3 = 1002;
constexpr int IDC_MP4 = 1003;
constexpr int IDC_RESOLUTION = 1004;
constexpr int IDC_DOWNLOAD = 1005;
constexpr int IDC_CANCEL = 1006;
constexpr int IDC_OUTPUT_LABEL = 1007;
constexpr int IDC_CHOOSE = 1008;
constexpr int IDC_SHOW_FILES = 1009;
constexpr int IDC_LOG = 1011;

constexpr UINT WM_APP_LOG = WM_APP + 1;
constexpr UINT WM_APP_DONE = WM_APP + 2;

const std::wstring kDefaultFirstRunLink = L"https://www.youtube.com/watch?v=dQw4w9WgXcQ\r\n";
const std::wstring kSpecialVideoID = L"dQw4w9WgXcQ";
const std::wstring kSpecialVideoDisplayName = L"Relaxing Sleep Sounds";
const std::vector<std::wstring> kSpecialVideoKnownTitles = {
    L"Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)",
    L"Rick Astley - Never Gonna Give You Up (Official Music Video)",
    L"Never Gonna Give You Up"
};

HINSTANCE g_instance = nullptr;
HWND g_window = nullptr;
HWND g_links = nullptr;
HWND g_mp3 = nullptr;
HWND g_mp4 = nullptr;
HWND g_resolution = nullptr;
HWND g_download = nullptr;
HWND g_cancel = nullptr;
HWND g_outputLabel = nullptr;
HWND g_choose = nullptr;
HWND g_showFiles = nullptr;
HWND g_log = nullptr;
HFONT g_font = nullptr;
HBRUSH g_downloadBrush = nullptr;
HBRUSH g_downloadDisabledBrush = nullptr;
WNDPROC g_originalLinksProc = nullptr;
HANDLE g_process = nullptr;
bool g_cancelRequested = false;

std::wstring g_supportDir;
std::wstring g_appDir;
std::wstring g_linksPath;
std::wstring g_settingsPath;
std::wstring g_outputDir;

void AppendLog(const std::wstring& text);

std::wstring QuoteArg(const std::wstring& value) {
    std::wstring quoted = L"\"";
    unsigned int slashCount = 0;

    for (wchar_t ch : value) {
        if (ch == L'\\') {
            slashCount++;
        } else if (ch == L'"') {
            quoted.append(slashCount * 2 + 1, L'\\');
            quoted.push_back(ch);
            slashCount = 0;
        } else {
            quoted.append(slashCount, L'\\');
            slashCount = 0;
            quoted.push_back(ch);
        }
    }

    quoted.append(slashCount * 2, L'\\');
    quoted.push_back(L'"');
    return quoted;
}

std::wstring JoinPath(const std::wstring& left, const std::wstring& right) {
    if (left.empty()) return right;
    if (left.back() == L'\\' || left.back() == L'/') return left + right;
    return left + L"\\" + right;
}

bool PathExists(const std::wstring& path) {
    return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

std::wstring DirectoryName(const std::wstring& path) {
    size_t index = path.find_last_of(L"\\/");
    if (index == std::wstring::npos) return L"";
    return path.substr(0, index);
}

std::wstring KnownFolder(REFKNOWNFOLDERID id) {
    PWSTR raw = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(id, KF_FLAG_CREATE, nullptr, &raw))) {
        std::wstring result(raw);
        CoTaskMemFree(raw);
        return result;
    }
    return L"";
}

void EnsureDirectory(const std::wstring& path) {
    SHCreateDirectoryExW(nullptr, path.c_str(), nullptr);
}

std::wstring ReadAllText(HWND edit) {
    int length = GetWindowTextLengthW(edit);
    std::wstring text(length, L'\0');
    if (length > 0) {
        GetWindowTextW(edit, text.data(), length + 1);
    }
    return text;
}

void ReplaceAll(std::wstring& value, const std::wstring& from, const std::wstring& to) {
    if (from.empty()) return;

    size_t position = 0;
    while ((position = value.find(from, position)) != std::wstring::npos) {
        value.replace(position, from.size(), to);
        position += to.size();
    }
}

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

std::wstring MaskSpecialVideoText(std::wstring text) {
    for (const auto& title : kSpecialVideoKnownTitles) {
        ReplaceAll(text, title, kSpecialVideoDisplayName);
    }

    std::wstring marker = L" [" + kSpecialVideoID + L"]";
    size_t markerPosition = 0;
    while ((markerPosition = text.find(marker, markerPosition)) != std::wstring::npos) {
        size_t lineStart = text.find_last_of(L"\r\n", markerPosition);
        lineStart = lineStart == std::wstring::npos ? 0 : lineStart + 1;

        size_t pathStart = text.find_last_of(L"\\/:\"", markerPosition);
        size_t replaceStart = pathStart == std::wstring::npos || pathStart < lineStart ? lineStart : pathStart + 1;

        text.replace(replaceStart, markerPosition - replaceStart, kSpecialVideoDisplayName);
        markerPosition = replaceStart + kSpecialVideoDisplayName.size() + marker.size();
    }

    return text;
}

std::wstring TrimCharacters(const std::wstring& value, const std::wstring& characters) {
    size_t start = 0;
    while (start < value.size() && characters.find(value[start]) != std::wstring::npos) start++;

    size_t end = value.size();
    while (end > start && characters.find(value[end - 1]) != std::wstring::npos) end--;

    return value.substr(start, end - start);
}

bool StartsWithInsensitive(const std::wstring& value, size_t offset, const std::wstring& prefix) {
    if (offset + prefix.size() > value.size()) return false;
    return ToLower(value.substr(offset, prefix.size())) == prefix;
}

std::vector<std::wstring> ExtractURLs(const std::wstring& text) {
    std::vector<std::wstring> urls;
    size_t index = 0;

    while (index < text.size()) {
        bool isHttp = StartsWithInsensitive(text, index, L"http://");
        bool isHttps = StartsWithInsensitive(text, index, L"https://");
        if (!isHttp && !isHttps) {
            index++;
            continue;
        }

        size_t end = index;
        while (end < text.size()) {
            wchar_t ch = text[end];
            if (iswspace(ch) || ch == L',' || ch == L'"' || ch == L'\'' || ch == L'<' || ch == L'>') break;
            end++;
        }

        urls.push_back(text.substr(index, end - index));
        index = end;
    }

    return urls;
}

std::vector<std::wstring> SplitLooseCandidates(const std::wstring& text) {
    std::vector<std::wstring> candidates;
    std::wstring current;

    for (wchar_t ch : text) {
        if (ch == L'\r') continue;
        if (ch == L'\n' || ch == L',' || ch == L'\t') {
            if (!current.empty()) {
                candidates.push_back(current);
                current.clear();
            }
        } else {
            current.push_back(ch);
        }
    }

    if (!current.empty()) {
        candidates.push_back(current);
    }

    return candidates;
}

std::wstring FirstPathSegment(const std::wstring& path) {
    size_t start = 0;
    while (start < path.size() && path[start] == L'/') start++;
    size_t end = path.find(L'/', start);
    return path.substr(start, end == std::wstring::npos ? std::wstring::npos : end - start);
}

std::wstring SecondPathSegment(const std::wstring& path) {
    size_t start = 0;
    while (start < path.size() && path[start] == L'/') start++;
    size_t firstEnd = path.find(L'/', start);
    if (firstEnd == std::wstring::npos) return L"";

    size_t secondStart = firstEnd + 1;
    size_t secondEnd = path.find(L'/', secondStart);
    return path.substr(secondStart, secondEnd == std::wstring::npos ? std::wstring::npos : secondEnd - secondStart);
}

std::wstring QueryValue(const std::wstring& query, const std::wstring& key) {
    size_t start = 0;
    while (start <= query.size()) {
        size_t end = query.find(L'&', start);
        std::wstring pair = query.substr(start, end == std::wstring::npos ? std::wstring::npos : end - start);
        size_t equals = pair.find(L'=');
        std::wstring name = equals == std::wstring::npos ? pair : pair.substr(0, equals);

        if (name == key) {
            return equals == std::wstring::npos ? L"" : pair.substr(equals + 1);
        }

        if (end == std::wstring::npos) break;
        start = end + 1;
    }

    return L"";
}

std::wstring NormalizedYouTubeURL(const std::wstring& rawURL) {
    size_t scheme = rawURL.find(L"://");
    if (scheme == std::wstring::npos) return L"";

    size_t hostStart = scheme + 3;
    size_t pathStart = rawURL.find(L'/', hostStart);
    std::wstring host = ToLower(rawURL.substr(hostStart, pathStart == std::wstring::npos ? std::wstring::npos : pathStart - hostStart));
    size_t port = host.find(L':');
    if (port != std::wstring::npos) host = host.substr(0, port);

    std::wstring pathAndQuery = pathStart == std::wstring::npos ? L"/" : rawURL.substr(pathStart);
    size_t fragmentStart = pathAndQuery.find(L'#');
    if (fragmentStart != std::wstring::npos) pathAndQuery = pathAndQuery.substr(0, fragmentStart);

    size_t queryStart = pathAndQuery.find(L'?');
    std::wstring path = queryStart == std::wstring::npos ? pathAndQuery : pathAndQuery.substr(0, queryStart);
    std::wstring query = queryStart == std::wstring::npos ? L"" : pathAndQuery.substr(queryStart + 1);

    std::wstring videoID;
    if (host == L"youtu.be" || (host.size() > 9 && host.substr(host.size() - 9) == L".youtu.be")) {
        videoID = FirstPathSegment(path);
    } else if (host == L"youtube.com" || (host.size() > 12 && host.substr(host.size() - 12) == L".youtube.com") ||
               host == L"youtube-nocookie.com" || (host.size() > 21 && host.substr(host.size() - 21) == L".youtube-nocookie.com")) {
        if (path == L"/watch") {
            videoID = QueryValue(query, L"v");
        } else {
            std::wstring first = FirstPathSegment(path);
            if (first == L"shorts" || first == L"embed" || first == L"live") {
                videoID = SecondPathSegment(path);
            }
        }
    }

    if (videoID.empty()) return L"";
    return L"https://www.youtube.com/watch?v=" + videoID;
}

std::wstring SanitizePastedLinks(const std::wstring& text) {
    std::vector<std::wstring> candidates = ExtractURLs(text);
    if (candidates.empty()) {
        candidates = SplitLooseCandidates(text);
    }

    std::vector<std::wstring> sanitized;
    for (const auto& candidate : candidates) {
        std::wstring trimmed = TrimCharacters(candidate, L" \t\r\n\"'<>.,;)");
        if (trimmed.empty()) continue;

        std::wstring normalized = NormalizedYouTubeURL(trimmed);
        sanitized.push_back(normalized.empty() ? trimmed : normalized);
    }

    if (sanitized.empty()) return text;

    std::wstring result;
    for (size_t i = 0; i < sanitized.size(); i++) {
        if (i > 0) result += L"\r\n";
        result += sanitized[i];
    }

    return result;
}

bool ShouldPrefixPasteWithNewline(HWND edit, const std::wstring& text) {
    if (text.empty() || text.front() == L'\r' || text.front() == L'\n') return false;

    DWORD selectionStart = 0;
    DWORD selectionEnd = 0;
    SendMessageW(edit, EM_GETSEL, reinterpret_cast<WPARAM>(&selectionStart), reinterpret_cast<LPARAM>(&selectionEnd));
    if (selectionStart == 0) return false;

    std::wstring currentText = ReadAllText(edit);
    size_t location = std::min<size_t>(selectionStart, currentText.size());
    if (location == 0) return false;

    size_t lineStart = currentText.rfind(L'\n', location - 1);
    lineStart = lineStart == std::wstring::npos ? 0 : lineStart + 1;
    if (location <= lineStart) return false;

    for (size_t i = lineStart; i < location; i++) {
        if (!iswspace(currentText[i])) return true;
    }

    return false;
}

LRESULT CALLBACK LinksEditProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_PASTE && OpenClipboard(hwnd)) {
        HANDLE clipboardData = GetClipboardData(CF_UNICODETEXT);
        if (clipboardData) {
            const wchar_t* rawText = static_cast<const wchar_t*>(GlobalLock(clipboardData));
            if (rawText) {
                std::wstring sanitized = SanitizePastedLinks(rawText);
                GlobalUnlock(clipboardData);
                if (ShouldPrefixPasteWithNewline(hwnd, sanitized)) {
                    sanitized = L"\r\n" + sanitized;
                }
                SendMessageW(hwnd, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(sanitized.c_str()));
                CloseClipboard();
                return 0;
            }
        }

        CloseClipboard();
    }

    return CallWindowProcW(g_originalLinksProc, hwnd, message, wParam, lParam);
}

void SetStatus(const std::wstring& text) {
    if (text.empty() || text == L"Ready") return;
    AppendLog(text + L"\n");
}

void AppendLog(const std::wstring& text) {
    std::wstring displayText = MaskSpecialVideoText(text);
    int length = GetWindowTextLengthW(g_log);
    SendMessageW(g_log, EM_SETSEL, length, length);
    std::wstring normalized;
    normalized.reserve(displayText.size() + 2);
    for (wchar_t ch : displayText) {
        if (ch == L'\r') continue;
        if (ch == L'\n') normalized += L"\r\n";
        else normalized.push_back(ch);
    }
    SendMessageW(g_log, EM_REPLACESEL, FALSE, reinterpret_cast<LPARAM>(normalized.c_str()));
    SendMessageW(g_log, EM_SCROLLCARET, 0, 0);
}

void ResetActivityLog() {
    SetWindowTextW(g_log, L"============\r\nActivity Log\r\n============\r\n\r\n");
}

std::wstring Utf8ToWide(const std::string& text) {
    if (text.empty()) return L"";
    int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
    UINT codePage = CP_UTF8;
    if (size <= 0) {
        codePage = CP_ACP;
        size = MultiByteToWideChar(codePage, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
    }
    if (size <= 0) return L"";

    std::wstring wide(size, L'\0');
    MultiByteToWideChar(codePage, 0, text.data(), static_cast<int>(text.size()), wide.data(), size);
    return wide;
}

std::string WideToUtf8(const std::wstring& text) {
    if (text.empty()) return "";
    int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    std::string utf8(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), utf8.data(), size, nullptr, nullptr);
    return utf8;
}

bool SearchExecutable(const std::wstring& name, std::wstring& found) {
    wchar_t buffer[MAX_PATH] = {};
    DWORD length = SearchPathW(nullptr, name.c_str(), nullptr, MAX_PATH, buffer, nullptr);
    if (length > 0 && length < MAX_PATH) {
        found = buffer;
        return true;
    }
    return false;
}

void SaveLinks() {
    EnsureDirectory(g_supportDir);
    std::ofstream out(g_linksPath.c_str(), std::ios::binary | std::ios::trunc);
    out << WideToUtf8(ReadAllText(g_links));
}

bool DefaultLinkWasSeeded() {
    wchar_t buffer[8] = {};
    GetPrivateProfileStringW(L"Settings", L"DefaultLinkSeeded", L"", buffer, ARRAYSIZE(buffer), g_settingsPath.c_str());
    return wcscmp(buffer, L"1") == 0;
}

void MarkDefaultLinkSeeded() {
    WritePrivateProfileStringW(L"Settings", L"DefaultLinkSeeded", L"1", g_settingsPath.c_str());
}

bool IsBlankText(const std::wstring& text) {
    return std::all_of(text.begin(), text.end(), [](wchar_t ch) {
        return iswspace(ch);
    });
}

void SeedDefaultLink() {
    std::ofstream out(g_linksPath.c_str(), std::ios::binary | std::ios::trunc);
    out << WideToUtf8(kDefaultFirstRunLink);
    MarkDefaultLinkSeeded();
    SetWindowTextW(g_links, kDefaultFirstRunLink.c_str());
}

void LoadLinks() {
    EnsureDirectory(g_supportDir);
    bool hasSeededDefaultLink = DefaultLinkWasSeeded();
    std::ifstream in(g_linksPath.c_str(), std::ios::binary);
    if (!in) {
        SeedDefaultLink();
        return;
    }

    std::ostringstream buffer;
    buffer << in.rdbuf();
    std::wstring text = Utf8ToWide(buffer.str());
    if (!hasSeededDefaultLink && IsBlankText(text)) {
        SeedDefaultLink();
        return;
    }

    if (!hasSeededDefaultLink) {
        MarkDefaultLinkSeeded();
    }
    SetWindowTextW(g_links, text.c_str());
}

std::wstring DefaultOutputDirectory() {
    std::wstring downloads = KnownFolder(FOLDERID_Downloads);
    if (downloads.empty()) downloads = JoinPath(KnownFolder(FOLDERID_Profile), L"Downloads");
    return JoinPath(downloads, L"YouTube Downloader");
}

std::wstring YoutubeDownloaderParentDirectory(const std::wstring& path) {
    size_t end = path.find_last_not_of(L"\\/");
    std::wstring trimmed = end == std::wstring::npos ? path : path.substr(0, end + 1);
    size_t separator = trimmed.find_last_of(L"\\/");
    std::wstring lastPart = separator == std::wstring::npos ? trimmed : trimmed.substr(separator + 1);

    if (_wcsicmp(lastPart.c_str(), L"YouTube Downloader") == 0) {
        return trimmed;
    }

    return JoinPath(trimmed, L"YouTube Downloader");
}

std::wstring CurrentDestinationDirectory() {
    return JoinPath(g_outputDir, IsDlgButtonChecked(g_window, IDC_MP4) == BST_CHECKED ? L"Video" : L"Audio");
}

std::wstring TrimWhitespace(const std::wstring& value) {
    size_t start = 0;
    while (start < value.size() && iswspace(value[start])) start++;

    size_t end = value.size();
    while (end > start && iswspace(value[end - 1])) end--;

    return value.substr(start, end - start);
}

std::wstring CollapseWhitespace(const std::wstring& value) {
    std::wstring result;
    bool previousWasSpace = false;

    for (wchar_t ch : value) {
        if (iswspace(ch)) {
            if (!previousWasSpace) {
                result.push_back(L' ');
            }
            previousWasSpace = true;
        } else {
            result.push_back(ch);
            previousWasSpace = false;
        }
    }

    return TrimWhitespace(result);
}

std::wstring CleanFilenameStem(const std::wstring& stem) {
    if (stem.find(kSpecialVideoID) != std::wstring::npos) {
        return kSpecialVideoDisplayName;
    }

    for (const auto& title : kSpecialVideoKnownTitles) {
        if (ToLower(stem).find(ToLower(title)) != std::wstring::npos) {
            return kSpecialVideoDisplayName;
        }
    }

    std::wstring result;
    bool insideBrackets = false;

    for (wchar_t ch : stem) {
        if (ch == L'[') {
            insideBrackets = true;
            continue;
        }

        if (insideBrackets) {
            if (ch == L']') {
                insideBrackets = false;
            }
            continue;
        }

        result.push_back(ch);
    }

    return CollapseWhitespace(result);
}

void CleanDownloadedFilenames(const std::wstring& directory) {
    WIN32_FIND_DATAW data = {};
    HANDLE handle = FindFirstFileW(JoinPath(directory, L"*").c_str(), &data);
    if (handle == INVALID_HANDLE_VALUE) return;

    do {
        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;

        std::wstring filename = data.cFileName;
        size_t dot = filename.find_last_of(L'.');
        std::wstring stem = dot == std::wstring::npos ? filename : filename.substr(0, dot);
        std::wstring ext = dot == std::wstring::npos ? L"" : filename.substr(dot);
        std::wstring cleanStem = CleanFilenameStem(stem);

        if (cleanStem.empty() || cleanStem == stem) continue;

        std::wstring originalPath = JoinPath(directory, filename);
        std::wstring targetPath = JoinPath(directory, cleanStem + ext);
        int suffix = 2;

        while (PathExists(targetPath)) {
            targetPath = JoinPath(directory, cleanStem + L" " + std::to_wstring(suffix) + ext);
            suffix++;
        }

        MoveFileW(originalPath.c_str(), targetPath.c_str());
    } while (FindNextFileW(handle, &data));

    FindClose(handle);
}

void SaveSettings() {
    WritePrivateProfileStringW(L"Settings", L"OutputDirectory", g_outputDir.c_str(), g_settingsPath.c_str());
    WritePrivateProfileStringW(L"Settings", L"Format", IsDlgButtonChecked(g_window, IDC_MP4) == BST_CHECKED ? L"mp4" : L"mp3", g_settingsPath.c_str());

    WritePrivateProfileStringW(L"Settings", L"Resolution", nullptr, g_settingsPath.c_str());
}

void LoadSettings() {
    wchar_t buffer[MAX_PATH * 4] = {};
    GetPrivateProfileStringW(L"Settings", L"OutputDirectory", L"", buffer, ARRAYSIZE(buffer), g_settingsPath.c_str());
    g_outputDir = buffer[0] ? YoutubeDownloaderParentDirectory(buffer) : DefaultOutputDirectory();

    wchar_t format[16] = {};
    GetPrivateProfileStringW(L"Settings", L"Format", L"mp3", format, ARRAYSIZE(format), g_settingsPath.c_str());
    CheckRadioButton(g_window, IDC_MP3, IDC_MP4, _wcsicmp(format, L"mp4") == 0 ? IDC_MP4 : IDC_MP3);
    EnableWindow(g_resolution, IsDlgButtonChecked(g_window, IDC_MP4) == BST_CHECKED);

    SendMessageW(g_resolution, CB_SETCURSEL, 0, 0);
}

void UpdateOutputLabel() {
    SetWindowTextW(g_outputLabel, g_outputDir.c_str());
}

void SetDownloading(bool downloading) {
    EnableWindow(g_download, !downloading);
    EnableWindow(g_cancel, downloading);
    EnableWindow(g_mp3, !downloading);
    EnableWindow(g_mp4, !downloading);
    EnableWindow(g_choose, !downloading);
    EnableWindow(g_showFiles, !downloading);
    EnableWindow(g_resolution, !downloading && IsDlgButtonChecked(g_window, IDC_MP4) == BST_CHECKED);
    InvalidateRect(g_download, nullptr, TRUE);
}

bool HasNonEmptyLink() {
    std::wistringstream stream(ReadAllText(g_links));
    std::wstring line;
    while (std::getline(stream, line)) {
        line.erase(line.begin(), std::find_if(line.begin(), line.end(), [](wchar_t ch) { return !iswspace(ch); }));
        if (!line.empty() && line[0] != L'#') return true;
    }
    return false;
}

std::wstring SelectedResolutionValue() {
    int index = static_cast<int>(SendMessageW(g_resolution, CB_GETCURSEL, 0, 0));
    switch (index) {
        case 1: return L"2160";
        case 2: return L"1080";
        case 3: return L"720";
        case 4: return L"480";
        default: return L"best";
    }
}

void OpenInstallHelper(const std::wstring& missingTools) {
    std::wstring helper = JoinPath(g_appDir, L"Install Required Tools.bat");
    DWORD attributes = GetFileAttributesW(helper.c_str());
    bool helperExists = attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);

    std::wstring message = missingTools + L" required.\n\n";
    message += L"Topher's YouTube Downloader stays lightweight by using yt-dlp and ffmpeg from Windows instead of bundling them.\n\n";
    message += helperExists
        ? L"Open Install Required Tools.bat now?"
        : L"Install yt-dlp and ffmpeg, then reopen the app and try again.";

    UINT buttons = helperExists ? MB_ICONWARNING | MB_YESNO : MB_ICONWARNING | MB_OK;
    int result = MessageBoxW(g_window, message.c_str(), L"Topher's YouTube Downloader", buttons);

    if (helperExists && result == IDYES) {
        ShellExecuteW(g_window, L"open", helper.c_str(), nullptr, g_appDir.c_str(), SW_SHOWNORMAL);
    }
}

std::wstring Mp4FormatSelector(const std::wstring& resolution) {
    if (resolution == L"2160") return L"bestvideo[height<=2160]+bestaudio[ext=m4a]/bestvideo[height<=2160]+bestaudio/best[height<=2160]";
    if (resolution == L"1080") return L"bestvideo[height<=1080][ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=1080]+bestaudio/best[height<=1080]";
    if (resolution == L"720") return L"bestvideo[height<=720][ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]";
    if (resolution == L"480") return L"bestvideo[height<=480][ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=480]+bestaudio/best[height<=480]";
    return L"bestvideo[ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo+bestaudio/best";
}

std::wstring BuildCommandLine(const std::wstring& ytDlp, const std::wstring& ffmpeg) {
    bool isMp4 = IsDlgButtonChecked(g_window, IDC_MP4) == BST_CHECKED;
    std::wstring destination = CurrentDestinationDirectory();
    std::wstring command = QuoteArg(ytDlp);
    command += L" --batch-file " + QuoteArg(g_linksPath);
    command += L" --newline";
    command += L" --ffmpeg-location " + QuoteArg(ffmpeg);
    command += L" --extractor-args " + QuoteArg(L"youtube:player_client=default,-web");
    command += L" --no-playlist";
    command += L" --replace-in-metadata title " + QuoteArg(L"\\s*\\[[^]]*\\]") + L" " + QuoteArg(L"");
    command += L" -P " + QuoteArg(destination);
    command += L" -o " + QuoteArg(L"%(title).200B [%(id)s].%(ext)s");

    if (isMp4) {
        std::wstring resolution = SelectedResolutionValue();
        command += L" -f " + QuoteArg(Mp4FormatSelector(resolution));
        command += L" --merge-output-format mp4";
        AppendLog(L"Resolution: " + resolution + L"\n");
    } else {
        command += L" -f " + QuoteArg(L"bestaudio/best");
        command += L" --extract-audio --audio-format mp3 --audio-quality 0";
    }

    return command;
}

DWORD WINAPI ReaderThread(void* parameter) {
    HANDLE readPipe = static_cast<HANDLE>(parameter);
    char buffer[4096];
    DWORD bytesRead = 0;

    while (ReadFile(readPipe, buffer, sizeof(buffer), &bytesRead, nullptr) && bytesRead > 0) {
        auto* text = new std::wstring(Utf8ToWide(std::string(buffer, buffer + bytesRead)));
        PostMessageW(g_window, WM_APP_LOG, 0, reinterpret_cast<LPARAM>(text));
    }

    CloseHandle(readPipe);
    WaitForSingleObject(g_process, INFINITE);

    DWORD exitCode = 1;
    GetExitCodeProcess(g_process, &exitCode);
    PostMessageW(g_window, WM_APP_DONE, static_cast<WPARAM>(exitCode), 0);
    return 0;
}

void StartDownload() {
    if (g_process) {
        SetStatus(L"Download in progress");
        return;
    }

    SaveLinks();
    SaveSettings();

    if (!HasNonEmptyLink()) {
        SetStatus(L"Add a link first");
        return;
    }

    std::wstring ytDlp;
    std::wstring ffmpeg;
    bool missingYtDlp = !SearchExecutable(L"yt-dlp.exe", ytDlp) && !SearchExecutable(L"yt-dlp", ytDlp);
    bool missingFfmpeg = !SearchExecutable(L"ffmpeg.exe", ffmpeg) && !SearchExecutable(L"ffmpeg", ffmpeg);

    if (missingYtDlp || missingFfmpeg) {
        std::wstring missingTools;
        if (missingYtDlp && missingFfmpeg) missingTools = L"yt-dlp and ffmpeg are";
        else if (missingYtDlp) missingTools = L"yt-dlp is";
        else missingTools = L"ffmpeg is";

        SetStatus(missingTools + L" not found");
        AppendLog(missingTools + L" not found.\nRun Install Required Tools.bat, then reopen the app.\n");
        OpenInstallHelper(missingTools);
        return;
    }

    std::wstring destination = CurrentDestinationDirectory();
    EnsureDirectory(destination);
    ResetActivityLog();
    AppendLog(IsDlgButtonChecked(g_window, IDC_MP4) == BST_CHECKED ? L"Starting MP4 download\n" : L"Starting MP3 download\n");
    AppendLog(L"Saving to " + destination + L"\n");

    SECURITY_ATTRIBUTES securityAttributes = {};
    securityAttributes.nLength = sizeof(securityAttributes);
    securityAttributes.bInheritHandle = TRUE;

    HANDLE readPipe = nullptr;
    HANDLE writePipe = nullptr;
    if (!CreatePipe(&readPipe, &writePipe, &securityAttributes, 0)) {
        SetStatus(L"Could not start download");
        AppendLog(L"CreatePipe failed\n");
        return;
    }
    SetHandleInformation(readPipe, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW startup = {};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdOutput = writePipe;
    startup.hStdError = writePipe;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    PROCESS_INFORMATION processInfo = {};
    std::wstring commandLine = BuildCommandLine(ytDlp, ffmpeg);
    std::vector<wchar_t> mutableCommand(commandLine.begin(), commandLine.end());
    mutableCommand.push_back(L'\0');

    g_cancelRequested = false;
    BOOL started = CreateProcessW(
        ytDlp.c_str(),
        mutableCommand.data(),
        nullptr,
        nullptr,
        TRUE,
        CREATE_NO_WINDOW,
        nullptr,
        g_supportDir.c_str(),
        &startup,
        &processInfo
    );

    CloseHandle(writePipe);

    if (!started) {
        CloseHandle(readPipe);
        SetStatus(L"Could not start download");
        AppendLog(L"CreateProcess failed\n");
        return;
    }

    CloseHandle(processInfo.hThread);
    g_process = processInfo.hProcess;
    SetDownloading(true);
    SetStatus(L"Downloading...");
    CreateThread(nullptr, 0, ReaderThread, readPipe, 0, nullptr);
}

void CancelDownload() {
    if (!g_process) return;
    g_cancelRequested = true;
    SetStatus(L"Canceling...");
    AppendLog(L"Cancel requested\n");
    TerminateProcess(g_process, 1);
}

void ChooseOutputFolder() {
    BROWSEINFOW browse = {};
    browse.hwndOwner = g_window;
    browse.lpszTitle = L"Choose where downloaded files should be saved.";
    browse.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;

    PIDLIST_ABSOLUTE pidl = SHBrowseForFolderW(&browse);
    if (!pidl) return;

    wchar_t path[MAX_PATH] = {};
    if (SHGetPathFromIDListW(pidl, path)) {
        g_outputDir = YoutubeDownloaderParentDirectory(path);
        UpdateOutputLabel();
        SaveSettings();
        SetStatus(L"Output folder updated");
    }
    CoTaskMemFree(pidl);
}

void Layout(HWND hwnd) {
    RECT rect;
    GetClientRect(hwnd, &rect);
    int width = rect.right - rect.left;
    int height = rect.bottom - rect.top;
    int margin = 18;
    int contentWidth = width - margin * 2;

    int linksHeight = std::max(170, (height - 235) / 2);
    MoveWindow(g_links, margin, margin, contentWidth, linksHeight, TRUE);

    int y = margin + linksHeight + 12;
    MoveWindow(g_mp3, margin, y, 60, 24, TRUE);
    MoveWindow(g_mp4, margin + 70, y, 60, 24, TRUE);
    MoveWindow(GetDlgItem(hwnd, 2001), margin + 145, y + 4, 72, 20, TRUE);
    MoveWindow(g_resolution, margin + 218, y, 145, 120, TRUE);
    MoveWindow(g_download, margin + 375, y, 90, 28, TRUE);
    MoveWindow(g_cancel, margin + 475, y, 80, 28, TRUE);

    y += 38;
    MoveWindow(GetDlgItem(hwnd, 2002), margin, y + 4, 58, 20, TRUE);
    MoveWindow(g_outputLabel, margin + 60, y + 4, std::max(120, contentWidth - 275), 20, TRUE);
    MoveWindow(g_choose, width - margin - 205, y, 90, 28, TRUE);
    MoveWindow(g_showFiles, width - margin - 105, y, 105, 28, TRUE);

    y += 34;
    MoveWindow(g_log, margin, y, contentWidth, std::max(110, height - y - margin), TRUE);
}

HWND MakeControl(const wchar_t* className, const wchar_t* text, DWORD style, int id, HWND parent) {
    HWND control = CreateWindowExW(
        0,
        className,
        text,
        WS_CHILD | WS_VISIBLE | style,
        0, 0, 10, 10,
        parent,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
        g_instance,
        nullptr
    );
    SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(g_font), TRUE);
    return control;
}

void DrawDownloadButton(const DRAWITEMSTRUCT* item) {
    bool disabled = (item->itemState & ODS_DISABLED) != 0;
    bool pressed = (item->itemState & ODS_SELECTED) != 0;

    RECT rect = item->rcItem;
    HBRUSH brush = disabled ? g_downloadDisabledBrush : g_downloadBrush;
    FillRect(item->hDC, &rect, brush);

    if (pressed) {
        OffsetRect(&rect, 1, 1);
    }

    SetBkMode(item->hDC, TRANSPARENT);
    SetTextColor(item->hDC, RGB(255, 255, 255));
    SelectObject(item->hDC, g_font);
    DrawTextW(item->hDC, L"Download", -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    if (item->itemState & ODS_FOCUS) {
        RECT focusRect = item->rcItem;
        InflateRect(&focusRect, -3, -3);
        DrawFocusRect(item->hDC, &focusRect);
    }
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
        case WM_CREATE: {
            g_window = hwnd;
            g_font = reinterpret_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
            g_downloadBrush = CreateSolidBrush(RGB(0, 122, 255));
            g_downloadDisabledBrush = CreateSolidBrush(RGB(122, 169, 219));

            g_links = MakeControl(L"EDIT", L"", WS_BORDER | ES_LEFT | ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL, IDC_LINKS, hwnd);
            g_originalLinksProc = reinterpret_cast<WNDPROC>(
                SetWindowLongPtrW(g_links, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(LinksEditProc))
            );
            SendMessageW(g_links, EM_SETCUEBANNER, FALSE, reinterpret_cast<LPARAM>(L"Paste YouTube link(s) here"));

            g_mp3 = MakeControl(L"BUTTON", L"MP3", BS_AUTORADIOBUTTON, IDC_MP3, hwnd);
            g_mp4 = MakeControl(L"BUTTON", L"MP4", BS_AUTORADIOBUTTON, IDC_MP4, hwnd);
            MakeControl(L"STATIC", L"Resolution:", 0, 2001, hwnd);

            g_resolution = MakeControl(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_TABSTOP, IDC_RESOLUTION, hwnd);
            SendMessageW(g_resolution, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"Best Available"));
            SendMessageW(g_resolution, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"4K (2160p)"));
            SendMessageW(g_resolution, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"1080p"));
            SendMessageW(g_resolution, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"720p"));
            SendMessageW(g_resolution, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"480p"));
            SendMessageW(g_resolution, CB_SETCURSEL, 0, 0);

            g_download = MakeControl(L"BUTTON", L"Download", BS_OWNERDRAW, IDC_DOWNLOAD, hwnd);
            g_cancel = MakeControl(L"BUTTON", L"Cancel", BS_PUSHBUTTON, IDC_CANCEL, hwnd);
            MakeControl(L"STATIC", L"Save to:", 0, 2002, hwnd);
            g_outputLabel = MakeControl(L"STATIC", L"", SS_PATHELLIPSIS, IDC_OUTPUT_LABEL, hwnd);
            g_choose = MakeControl(L"BUTTON", L"Save to...", BS_PUSHBUTTON, IDC_CHOOSE, hwnd);
            g_showFiles = MakeControl(L"BUTTON", L"Open", BS_PUSHBUTTON, IDC_SHOW_FILES, hwnd);
            g_log = MakeControl(L"EDIT", L"", WS_BORDER | ES_LEFT | ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY | WS_VSCROLL | WS_HSCROLL, IDC_LOG, hwnd);
            ResetActivityLog();

            LoadSettings();
            LoadLinks();
            UpdateOutputLabel();
            SetDownloading(false);
            Layout(hwnd);
            return 0;
        }

        case WM_SIZE:
            Layout(hwnd);
            return 0;

        case WM_COMMAND: {
            int id = LOWORD(wParam);
            if (id == IDC_MP3 || id == IDC_MP4) {
                EnableWindow(g_resolution, id == IDC_MP4 && !g_process);
                SaveSettings();
            } else if (id == IDC_RESOLUTION && HIWORD(wParam) == CBN_SELCHANGE) {
                SaveSettings();
            } else if (id == IDC_DOWNLOAD) {
                StartDownload();
            } else if (id == IDC_CANCEL) {
                CancelDownload();
            } else if (id == IDC_CHOOSE) {
                ChooseOutputFolder();
            } else if (id == IDC_SHOW_FILES) {
                std::wstring destination = CurrentDestinationDirectory();
                EnsureDirectory(destination);
                ShellExecuteW(hwnd, L"open", destination.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
            }
            return 0;
        }

        case WM_DRAWITEM: {
            auto* item = reinterpret_cast<DRAWITEMSTRUCT*>(lParam);
            if (item && item->CtlID == IDC_DOWNLOAD) {
                DrawDownloadButton(item);
                return TRUE;
            }
            break;
        }

        case WM_APP_LOG: {
            auto* text = reinterpret_cast<std::wstring*>(lParam);
            AppendLog(*text);
            delete text;
            return 0;
        }

        case WM_APP_DONE: {
            DWORD exitCode = static_cast<DWORD>(wParam);
            if (g_process) {
                CloseHandle(g_process);
                g_process = nullptr;
            }
            SetDownloading(false);

            if (g_cancelRequested) {
                g_cancelRequested = false;
                SetStatus(L"Canceled");
                AppendLog(L"Canceled\n");
            } else if (exitCode == 0) {
                CleanDownloadedFilenames(CurrentDestinationDirectory());
                SetStatus(L"Done");
                AppendLog(L"Finished\n");
                AppendLog(L"Saved files in " + CurrentDestinationDirectory() + L"\n");
            } else {
                SetStatus(L"Download failed");
                AppendLog(L"Download failed\nStopped with status " + std::to_wstring(exitCode) + L"\n");
            }
            return 0;
        }

        case WM_CLOSE:
            SaveLinks();
            SaveSettings();
            if (g_process) TerminateProcess(g_process, 1);
            DestroyWindow(hwnd);
            return 0;

        case WM_DESTROY:
            if (g_downloadBrush) DeleteObject(g_downloadBrush);
            if (g_downloadDisabledBrush) DeleteObject(g_downloadDisabledBrush);
            PostQuitMessage(0);
            return 0;
    }

    return DefWindowProcW(hwnd, message, wParam, lParam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCommand) {
    g_instance = instance;
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    wchar_t modulePath[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, modulePath, ARRAYSIZE(modulePath));
    g_appDir = DirectoryName(modulePath);

    std::wstring appData = KnownFolder(FOLDERID_RoamingAppData);
    if (appData.empty()) appData = JoinPath(KnownFolder(FOLDERID_Profile), L"AppData\\Roaming");
    g_supportDir = JoinPath(appData, L"YouTube Downloader");
    g_linksPath = JoinPath(g_supportDir, L"video.txt");
    g_settingsPath = JoinPath(g_supportDir, L"settings.ini");
    EnsureDirectory(g_supportDir);

    INITCOMMONCONTROLSEX commonControls = {};
    commonControls.dwSize = sizeof(commonControls);
    commonControls.dwICC = ICC_STANDARD_CLASSES;
    InitCommonControlsEx(&commonControls);

    WNDCLASSW windowClass = {};
    windowClass.lpfnWndProc = WindowProc;
    windowClass.hInstance = instance;
    windowClass.lpszClassName = L"YouTubeDownloaderWindow";
    windowClass.hCursor = LoadCursor(nullptr, IDC_ARROW);
    windowClass.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(1));
    windowClass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    RegisterClassW(&windowClass);

    HWND hwnd = CreateWindowExW(
        0,
        windowClass.lpszClassName,
        L"Topher's YouTube Downloader",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        780,
        700,
        nullptr,
        nullptr,
        instance,
        nullptr
    );

    if (!hwnd) return 1;

    ShowWindow(hwnd, showCommand);
    UpdateWindow(hwnd);

    MSG message = {};
    while (GetMessageW(&message, nullptr, 0, 0)) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    CoUninitialize();
    return static_cast<int>(message.wParam);
}
