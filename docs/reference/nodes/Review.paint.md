# Review.paint

How the review rules read the painted bounds of an image.

For an image, the rules use its painted bounds: the smallest rectangle that
holds its pixels of alpha 0.1 or more. `paintRect` on `UI.Image` declares
them. Without it, `review.collect` reads the pixels in Studio, one time for
each asset, and can yield. Studio reads only an image that the Studio user or
the experience owner can load. For other images, and outside Studio, the
rules use the rectangle of the part; declare `paintRect` there. An image with
no such pixel is not a cover or a backing. An image of 35% of the screen or
more is a ground or an overlay.

`review.paintRect(image) -> ImagePaintRect?` reads the painted bounds and the
pixel size of an image in Studio, in the form that `paintRect` takes. It can
yield. It returns nil outside Studio and for an image that Studio cannot
read. The art of a stack `ground` counts as built beside the texts of that
stack, and `escaped-text` always measures those texts against its paint.
The art of a theme skin counts as built in the part that wears the skin.

A text sits on the paint when half or more of its glyphs are over the painted
bounds. `escaped-text` then uses the edge of the paint. A text that is mostly
on the transparent margin, such as a count in the corner of a subject, is
measured against the rectangle. The painted bounds are a rectangle: a hole in
the paint, such as the middle of a frame, counts as paint. A part that is turned by a quarter turn is read at its turned
rectangle. A part at another angle is not used as a cover or as a backing.

Back to [Review.layout](Review.layout.md).
