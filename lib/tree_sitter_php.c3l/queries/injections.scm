((comment) @injection.content
  (#set! injection.language "phpdoc"))

(heredoc
  (heredoc_body) @injection.content
  (heredoc_end) @injection.language)

(nowdoc
  (nowdoc_body) @injection.content
  (heredoc_end) @injection.language)

; Yun-specific: the php grammar exposes markup outside <?php ?> as opaque
; (text) nodes, which upstream does not inject. Parse them as HTML. The markup
; is split into one (text) node per PHP block, so combine them into a single
; HTML parse or stray closing tags (e.g. </body>) become ERROR nodes.
((text) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined))
