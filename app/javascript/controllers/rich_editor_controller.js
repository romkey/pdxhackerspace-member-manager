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
      toolbar: 'undo redo | blocks | bold italic underline strikethrough | forecolor backcolor | alignleft aligncenter alignright | bullist numlist | link table | insertvariable | code',
      content_style: 'body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; font-size: 14px; line-height: 1.5; }',
      
      // Email-safe HTML settings
      valid_elements: 'p[style],br,strong/b,em/i,u,s,strike,h1[style],h2[style],h3[style],h4[style],h5[style],h6[style],ul,ol,li,a[href|target],table[style|border|cellpadding|cellspacing|width],tbody,thead,tr,td[style|colspan|rowspan],th[style|colspan|rowspan],span[style],div[style],img[src|alt|width|height|style]',
      valid_styles: {
        '*': 'color,background-color,font-size,font-weight,font-style,text-decoration,text-align,padding,margin,border,width,height'
      },

      // Sync content back to textarea before form submission
      setup: function(editor) {
        controller.editor = editor

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
        editor.on('change', function() {
          editor.save()
        })

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
