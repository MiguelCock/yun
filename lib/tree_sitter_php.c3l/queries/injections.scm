((comment) @injection.content
  (#set! injection.language "phpdoc"))

(heredoc
  (heredoc_body) @injection.content
  (heredoc_end) @injection.language)

(nowdoc
  (nowdoc_body) @injection.content
  (heredoc_end) @injection.language)

; Yun-specific: the php grammar exposes markup outside <?php ?> as a single
; opaque (text) node, which upstream does not inject. Parse it as HTML.
((text) @injection.content
  (#set! injection.language "html"))
