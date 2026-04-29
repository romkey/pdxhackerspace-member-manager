import { Controller } from "@hotwired/stimulus"

// Rich text editor controller using TinyMCE
// Provides visual WYSIWYG editing with HTML source toggle
export default class extends Controller {
  static targets = ["editor"]
  static values = {
    variables: Array
  }

  connect() {
    this.initEditor()
  }

  disconnect() {
    // Clean up TinyMCE instance when navigating away (Turbo compatibility)
    if (this.editor) {
      this.editor.destroy()
      this.editor = null
    }
  }

  initEditor() {
    const textarea = this.editorTarget
    const variables = this.variablesValue || []
    const controller = this

    if (typeof tinymce === "undefined") return

    // Build menu items for variable insertion
    const variableMenuItems = variables.map(v => ({
      type: 'menuitem',
      text: v.name,
      onAction: function() {
        controller.editor.insertContent(v.value)
      }
    }))

    tinymce.init({
      target: textarea,
      height: 400,
      menubar: false,
      plugins: 'link lists code table',
      toolbar: 'undo redo | blocks fontfamily fontsize | bold italic underline strikethrough | forecolor backcolor | alignleft aligncenter alignright | bullist numlist | link table | insertvariable | code',
      font_family_formats: 'System UI=-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; Arial=arial, helvetica, sans-serif; Georgia=georgia, palatino, serif; Helvetica=helvetica, arial, sans-serif; Tahoma=tahoma, geneva, sans-serif; Times New Roman=times new roman, times, serif; Trebuchet MS=trebuchet ms, geneva, sans-serif; Verdana=verdana, geneva, sans-serif; Courier New=courier new, courier, monospace',
      font_size_formats: '10px 12px 14px 16px 18px 20px 24px 28px 32px',
      content_style: 'body { font-family: arial, helvetica, sans-serif; font-size: 14px; line-height: 1.5; }',

      valid_elements: 'p[style],br,strong/b,em/i,u,s,strike,h1[style],h2[style],h3[style],h4[style],h5[style],h6[style],ul,ol,li,a[href|target],table[style|border|cellpadding|cellspacing|width],tbody,thead,tr,td[style|colspan|rowspan],th[style|colspan|rowspan],span[style],div[style],img[src|alt|width|height|style]',
      valid_styles: {
        '*': 'font-family,font-size,color,background-color,font-weight,font-style,text-decoration,text-align,padding,margin,border,width,height'
      },

      // Sync content back to textarea before form submission
      setup: function(editor) {
        controller.editor = editor

        const syncTextarea = function() {
          editor.save()
          textarea.dispatchEvent(new CustomEvent("rich-editor:change", { bubbles: true }))
        }

        // Add custom variable insertion button
        if (variableMenuItems.length > 0) {
          editor.ui.registry.addMenuButton('insertvariable', {
            text: 'Insert Variable',
            fetch: function(callback) {
              callback(variableMenuItems)
            }
          })
        }

        // Sync content to textarea on change
        editor.on('change keyup undo redo setcontent', syncTextarea)

        // Sync before form submission
        editor.on('submit', function() {
          editor.save()
        })
      },

      // Handle form submission
      init_instance_callback: function(editor) {
        // Find parent form and sync content before submit
        const form = textarea.closest('form')
        if (form) {
          form.addEventListener('submit', function() {
            editor.save()
          })
        }
      }
    })
  }
}
