// init dark mode
var darkMode = localStorage.getItem('page-dark-mode')
if (darkMode) document.body.classList.add("page-dark-mode")

window.onload = function () {

  document.getElementById("change-skin").onclick = function() {
    var darkMode = localStorage.getItem('page-dark-mode')

    if (darkMode) {
      localStorage.removeItem('page-dark-mode')
      document.body.classList.remove("page-dark-mode")
    } else {
      localStorage.setItem('page-dark-mode', true)
      document.body.classList.add("page-dark-mode")
    }
    BeautifulJekyllJS.initNavbar();
  };
}
