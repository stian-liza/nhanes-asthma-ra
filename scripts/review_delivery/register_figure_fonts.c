/* Register project-local static fonts in this R process only (macOS CoreText). */
#include <CoreText/CoreText.h>
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>
void register_figure_font(char **path, int *ok) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL,
        (const UInt8 *)path[0], strlen(path[0]), false);
    CFErrorRef error = NULL;
    *ok = CTFontManagerRegisterFontsForURL(url, kCTFontManagerScopeProcess, &error);
    if (error) CFRelease(error);
    CFRelease(url);
}
