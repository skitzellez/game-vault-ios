// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the OpenGL ES side of the player, for cores that draw with the phone's GPU (N64, PSP):
// one context, one framebuffer the core draws into, and reading the finished picture back for the screen layer.
#define GLES_SILENCE_DEPRECATION
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#include <dlfcn.h>

#include "host_gl.h"

static EAGLContext *context;
static GLuint fbo, color, depth;
static int fbo_w, fbo_h;

int gv_gl_create(int major) {
    context = [[EAGLContext alloc] initWithAPI:major >= 3 ? kEAGLRenderingAPIOpenGLES3 : kEAGLRenderingAPIOpenGLES2];
    if (!context) return -1;
    [EAGLContext setCurrentContext:context];
    return 0;
}

int gv_gl_framebuffer(int width, int height, int want_depth, int want_stencil) {
    if (!context) return -1;
    [EAGLContext setCurrentContext:context];
    fbo_w = width;
    fbo_h = height;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenTextures(1, &color);
    glBindTexture(GL_TEXTURE_2D, color);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, color, 0);
    if (want_depth || want_stencil) {
        glGenRenderbuffers(1, &depth);
        glBindRenderbuffer(GL_RENDERBUFFER, depth);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, depth);
    }
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    return status == GL_FRAMEBUFFER_COMPLETE ? 0 : -1;
}

void gv_gl_current(void) {
    if (context && [EAGLContext currentContext] != context) [EAGLContext setCurrentContext:context];
}

unsigned gv_gl_fbo(void) {
    return fbo;
}

void *gv_gl_proc(const char *name) {
    return dlsym(RTLD_DEFAULT, name);
}

int gv_gl_read(void *rgba, int width, int height) {
    if (!context || width > fbo_w || height > fbo_h) return -1;
    gv_gl_current();
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
    return 0;
}

void gv_gl_destroy(void) {
    if (!context) return;
    gv_gl_current();
    if (depth) glDeleteRenderbuffers(1, &depth);
    if (color) glDeleteTextures(1, &color);
    if (fbo) glDeleteFramebuffers(1, &fbo);
    depth = color = fbo = 0;
    fbo_w = fbo_h = 0;
    [EAGLContext setCurrentContext:nil];
    context = nil;
}
