import { Controller } from "@hotwired/stimulus"

// Botão "Copiar" ao lado de valores como api_key (ver
// app/views/admin/accounts/show.html.erb).
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    await navigator.clipboard.writeText(this.sourceTarget.textContent.trim())

    const original = this.buttonTarget.textContent
    this.buttonTarget.textContent = "Copiado!"

    setTimeout(() => {
      this.buttonTarget.textContent = original
    }, 1500)
  }
}
