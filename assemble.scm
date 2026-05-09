(define (assemble)
  (script-fu-use-v3)
  (let* ((image (gimp-image-new 1280 720 0))
         (bg (gimp-file-load-layer 1 image "background.png"))
         (logo (gimp-file-load-layer 1 image "./assets/icons/logo/ghost.png"))
         (ghost (gimp-file-load-layer 1 image "text_ghost.png"))
         (tuts (gimp-file-load-layer 1 image "text_tutorials.png")))

    (gimp-image-insert-layer image bg 0 0)
    
    (gimp-image-insert-layer image logo 0 0)
    (gimp-layer-scale logo 450 450 1)
    (gimp-layer-set-offsets logo 120 135)

    (gimp-image-insert-layer image ghost 0 0)
    (gimp-layer-set-offsets ghost 650 180)

    (gimp-image-insert-layer image tuts 0 0)
    (gimp-layer-set-offsets tuts 650 380)

    (gimp-file-save 1 image bg "youtube_thumbnail_gimp.xcf" "youtube_thumbnail_gimp.xcf")
    
    (let ((merged (gimp-image-merge-visible-layers image 0)))
      (gimp-file-save 1 image merged "youtube_thumbnail_gimp.png" "youtube_thumbnail_gimp.png"))

    (gimp-image-delete image))
  (gimp-quit 0))

(assemble)
