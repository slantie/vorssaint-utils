// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Private, bounded static SVG renderer. ThorVG is built without file IO;
// SVG resources cannot open arbitrary files. Only explicitly passed input
// and output paths and the fixed system fallback font are accessed here.
#include <thorvg.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <vector>

static bool readFile(const char* path, std::vector<char>& bytes, size_t limit) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return false;
    struct stat info;
    bool ok = fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_size > 0 && uint64_t(info.st_size) <= limit;
    if (ok) {
        bytes.resize(size_t(info.st_size));
        size_t offset = 0;
        while (offset < bytes.size()) {
            ssize_t count = read(fd, bytes.data() + offset, bytes.size() - offset);
            if (count <= 0) { ok = false; break; }
            offset += size_t(count);
        }
    }
    close(fd);
    return ok;
}

int main(int argc, char** argv) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        puts("Vorssaint SVG renderer / ThorVG 1.1.2 / static, no file IO"); return 0;
    }
    if (argc != 3) { fputs("Expected SVG input and PNG output.\n", stderr); return 1; }
    std::vector<char> source;
    if (!readFile(argv[1], source, 10 * 1024 * 1024)) return 2;
    if (tvg::Initializer::init(2) != tvg::Result::Success) return 3;
    int status = 4;
    {
        std::vector<char> font;
        if (readFile("/System/Library/Fonts/Supplemental/Arial.ttf", font, 16 * 1024 * 1024))
            tvg::Text::load("Arial", font.data(), uint32_t(font.size()), "ttf", false);
        auto picture = tvg::Picture::gen();
        float fw = 0, fh = 0;
        if (picture->load(source.data(), uint32_t(source.size()), "svg", nullptr, true) == tvg::Result::Success &&
            picture->size(&fw, &fh) == tvg::Result::Success && std::isfinite(fw) && std::isfinite(fh) &&
            fw > 0 && fh > 0 && fw <= 20000 && fh <= 20000 && std::ceil(fw) * std::ceil(fh) <= 64000000) {
            uint32_t w = uint32_t(std::ceil(fw)), h = uint32_t(std::ceil(fh));
            std::vector<uint32_t> pixels(size_t(w) * h, 0);
            std::unique_ptr<tvg::SwCanvas> canvas(tvg::SwCanvas::gen());
            if (canvas && canvas->target(pixels.data(), w, w, h, tvg::ColorSpace::ARGB8888) == tvg::Result::Success &&
                canvas->add(picture) == tvg::Result::Success && canvas->draw(true) == tvg::Result::Success &&
                canvas->sync() == tvg::Result::Success) {
                // ARGB8888 words are BGRA bytes on little-endian Apple Silicon.
                auto color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                auto provider = CGDataProviderCreateWithData(nullptr, pixels.data(), pixels.size() * 4, nullptr);
                auto image = CGImageCreate(w, h, 8, 32, size_t(w) * 4, color,
                    kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, provider, nullptr, false, kCGRenderingIntentDefault);
                auto data = CFDataCreateMutable(nullptr, 0);
                auto destination = CGImageDestinationCreateWithData(data, CFSTR("public.png"), 1, nullptr);
                if (image && destination) {
                    CGImageDestinationAddImage(destination, image, nullptr);
                    if (CGImageDestinationFinalize(destination)) {
                        int fd = open(argv[2], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
                        if (fd >= 0) {
                            const UInt8* bytes = CFDataGetBytePtr(data);
                            size_t length = size_t(CFDataGetLength(data)), offset = 0;
                            while (offset < length) {
                                ssize_t count = write(fd, bytes + offset, length - offset);
                                if (count <= 0) break;
                                offset += size_t(count);
                            }
                            bool closed = close(fd) == 0;
                            status = offset == length && closed ? 0 : 5;
                            if (status) unlink(argv[2]);
                        }
                    }
                }
                if (destination) CFRelease(destination);
                CFRelease(data);
                if (image) CGImageRelease(image);
                CGDataProviderRelease(provider);
                CGColorSpaceRelease(color);
            }
        }
        tvg::Text::unload("Arial");
    }
    tvg::Initializer::term();
    if (status) fputs("The static SVG could not be rendered within the image limits.\n", stderr);
    return status;
}
