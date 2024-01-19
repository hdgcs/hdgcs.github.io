$(function() {
  const items = $.map($("article").find("h1,h2,h3,h4,h5,h6"), function (el, _) {
    const level = el.tagName.replace("H", "");
    const anchor = el.id;
    const href = `#${encodeURI(anchor)}`;
    return `<a href="${href}" class="dropdown-item ml-${(level - 2) * 2}">${el.textContent}</a>`;
  });
  if (items.length) {
    $('[aria-labelledby="dropdownTocButton"]').html(items.join(""));
  }
})
