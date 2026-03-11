const RoomCommentEnterSubmit = {
  mounted() {
    this.onKeydown = (event) => {
      if (event.key !== "Enter" || event.shiftKey || event.isComposing) {
        return
      }

      const body = typeof this.el.value === "string" ? this.el.value.trim() : ""
      const form = this.el.form

      if (body === "" || !form) {
        return
      }

      event.preventDefault()
      form.requestSubmit()
    }

    this.el.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    if (this.onKeydown) {
      this.el.removeEventListener("keydown", this.onKeydown)
    }
  },
}

export default RoomCommentEnterSubmit
