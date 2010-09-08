/*
 * Copyright (C) 2003, 2004, 2005, 2006 Apple Computer, Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#import "config.h"
#import "GraphicsContext.h"

#import "GraphicsContextPlatformPrivateCG.h"
#import <AppKit/AppKit.h>
#import <wtf/StdLibExtras.h>

#import "WebCoreSystemInterface.h"

@class NSColor;

// FIXME: More of this should use CoreGraphics instead of AppKit.
// FIXME: More of this should move into GraphicsContextCG.cpp.

namespace WebCore {

// NSColor, NSBezierPath, and NSGraphicsContext
// calls in this file are all exception-safe, so we don't block
// exceptions for those.

static void drawFocusRingToContext(CGContextRef context, RetainPtr<CGPathRef> focusRingPath, RetainPtr<CGColorRef> colorRef, int radius)
{
#ifdef BUILDING_ON_TIGER
    CGContextBeginTransparencyLayer(context, 0);
#endif
    CGContextBeginPath(context);
    CGContextAddPath(context, focusRingPath.get());
    wkDrawFocusRing(context, colorRef.get(), radius);
#ifdef BUILDING_ON_TIGER
    CGContextEndTransparencyLayer(context);
#endif
}

void GraphicsContext::drawFocusRing(const Vector<Path>& paths, int width, int offset, const Color& color)
{
    if (paintingDisabled())
        return;
    
    int radius = (width - 1) / 2;
    offset += radius;
    RetainPtr<CGColorRef> colorRef;
    if (color.isValid())
        colorRef.adoptCF(createCGColor(color));
    
    RetainPtr<CGMutablePathRef> focusRingPath(AdoptCF, CGPathCreateMutable());
    unsigned pathCount = paths.size();
    for (unsigned i = 0; i < pathCount; i++)
        CGPathAddPath(focusRingPath.get(), 0, paths[i].platformPath());
    
    drawFocusRingToContext(platformContext(), focusRingPath, colorRef, radius);
}    
    
void GraphicsContext::drawFocusRing(const Vector<IntRect>& rects, int width, int offset, const Color& color)
{
    if (paintingDisabled())
        return;

    int radius = (width - 1) / 2;
    offset += radius;
    RetainPtr<CGColorRef> colorRef;
    if (color.isValid())
        colorRef.adoptCF(createCGColor(color));

    RetainPtr<CGMutablePathRef> focusRingPath(AdoptCF, CGPathCreateMutable());
    unsigned rectCount = rects.size();
    for (unsigned i = 0; i < rectCount; i++)
        CGPathAddRect(focusRingPath.get(), 0, CGRectInset(rects[i], -offset, -offset));

    drawFocusRingToContext(platformContext(), focusRingPath, colorRef, radius);
}

#ifdef BUILDING_ON_TIGER // Post-Tiger's setCompositeOperation() is defined in GraphicsContextCG.cpp.
void GraphicsContext::setCompositeOperation(CompositeOperator op)
{
    if (paintingDisabled())
        return;
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [[NSGraphicsContext graphicsContextWithGraphicsPort:platformContext() flipped:YES]
        setCompositingOperation:(NSCompositingOperation)op];
    [pool drain];
}
#endif

static NSColor* createPatternColor(NSString* name, NSColor* defaultColor, bool& usingDot)
{
    NSImage *image = [NSImage imageNamed:name];
    ASSERT(image); // if image is not available, we want to know
    NSColor *color = (image ? [NSColor colorWithPatternImage:image] : nil);
    if (color)
        usingDot = true;
    else
        color = defaultColor;
    return color;
}

// WebKit on Mac is a standard platform component, so it must use the standard platform artwork for underline.
void GraphicsContext::drawLineForTextChecking(const IntPoint& point, int width, TextCheckingLineStyle style)
{
    if (paintingDisabled())
        return;
        
    // These are the same for misspelling or bad grammar.
    int patternHeight = cMisspellingLineThickness;
    int patternWidth = cMisspellingLinePatternWidth;

    bool usingDot;
    NSColor *patternColor;
    switch (style) {
        case TextCheckingSpellingLineStyle:
        {
            // Constants for spelling pattern color.
            static bool usingDotForSpelling = false;
            DEFINE_STATIC_LOCAL(RetainPtr<NSColor>, spellingPatternColor, (createPatternColor(@"SpellingDot", [NSColor redColor], usingDotForSpelling)));
            usingDot = usingDotForSpelling;
            patternColor = spellingPatternColor.get();
            break;
        }
        case TextCheckingGrammarLineStyle:
        {
            // Constants for grammar pattern color.
            static bool usingDotForGrammar = false;
            DEFINE_STATIC_LOCAL(RetainPtr<NSColor>, grammarPatternColor, (createPatternColor(@"GrammarDot", [NSColor greenColor], usingDotForGrammar)));
            usingDot = usingDotForGrammar;
            patternColor = grammarPatternColor.get();
            break;
        }
#if PLATFORM(MAC) && !defined(BUILDING_ON_TIGER) && !defined(BUILDING_ON_LEOPARD) && !defined(BUILDING_ON_SNOW_LEOPARD)
        case TextCheckingReplacementLineStyle:
        {
            // Constants for spelling pattern color.
            static bool usingDotForSpelling = false;
            DEFINE_STATIC_LOCAL(RetainPtr<NSColor>, spellingPatternColor, (createPatternColor(@"CorrectionDot", [NSColor blueColor], usingDotForSpelling)));
            usingDot = usingDotForSpelling;
            patternColor = spellingPatternColor.get();
            break;
        }
#endif
        default:
            return;
    }

    // Make sure to draw only complete dots.
    // NOTE: Code here used to shift the underline to the left and increase the width
    // to make sure everything gets underlined, but that results in drawing out of
    // bounds (e.g. when at the edge of a view) and could make it appear that the
    // space between adjacent misspelled words was underlined.
    if (usingDot) {
        // allow slightly more considering that the pattern ends with a transparent pixel
        int widthMod = width % patternWidth;
        if (patternWidth - widthMod > cMisspellingLinePatternGapWidth)
            width -= widthMod;
    }
    
    // FIXME: This code should not use NSGraphicsContext currentContext
    // In order to remove this requirement we will need to use CGPattern instead of NSColor
    // FIXME: This code should not be using wkSetPatternPhaseInUserSpace, as this approach is wrong
    // for transforms.

    // Draw underline.
    NSGraphicsContext *currentContext = [NSGraphicsContext currentContext];
    CGContextRef context = (CGContextRef)[currentContext graphicsPort];
    CGContextSaveGState(context);

    [patternColor set];

    wkSetPatternPhaseInUserSpace(context, point);

    NSRectFillUsingOperation(NSMakeRect(point.x(), point.y(), width, patternHeight), NSCompositeSourceOver);
    
    CGContextRestoreGState(context);
}

}
