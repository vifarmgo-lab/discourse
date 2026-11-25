(() => {
  if (window.vnRankNavigation) return;
  window.vnRankNavigation = true;
  let oldPath, promise, scheduled = false;
  function link(text, href) {
    const a = document.createElement("a");
    a.href = href;
    a.textContent = text;
    a.className = "btn btn-flat";
    a.addEventListener("click", (e) => {
      if (e.button === 0 && !e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        e.stopPropagation();
        window.location.assign(a.href);
      }
    });
    return a;
  }
  async function draw() {
    const path = location.pathname;
    const topic = path.match(/^\/t\/(?:(?!\d+(?:\/|$))[^/]+\/)?(\d+)(?:\/\d+)?\/?$/);
    const profile = path.match(/^\/u\/([^/]+)/);
    const home = /^\/(?:latest|categories|top|hot|new|unread)?\/?$/.test(path);
    if (path !== oldPath) {
      document.querySelector("[data-vn-rank-nav]")?.remove();
      oldPath = path;
      promise = null;
    }
    if ((!topic && !profile && !home) || document.querySelector("[data-vn-rank-nav]")) return;
    const target = document.querySelector(topic ? "#topic-title" : profile ? ".user-main .about, .user-main" : ".list-controls, .navigation-container, .discovery-list-container");
    if (!target) return;
    const box = document.createElement("div");
    box.dataset.vnRankNav = "1";
    box.setAttribute("aria-label", "Danh hiệu VNBot");
    target.insertAdjacentElement("afterend", box);
    if (home) box.append(link("Lộ trình chuyên gia", "/lo-trinh"), link("Tiến độ của tôi", "/lo-trinh?tab=me"));
    const query = topic ? "?topic=" + topic[1] : profile ? "?name=" + profile[1] : "";
    promise ||= fetch("/lo-trinh/spotlight" + query, {headers:{Accept:"application/json"}})
      .then(r => r.ok ? r.json() : {}).catch(() => ({}));
    const data = await promise;
    if (!box.isConnected || location.pathname !== path) return;
    if (topic && data.eligible) box.append(link("Tôi muốn thử workflow này", "/lo-trinh?tab=trials&topic=" + topic[1]));
    if (profile && data.mine) box.append(link("Tiến độ danh hiệu của tôi", "/lo-trinh?tab=me"));
    if (profile && data.ranked) box.append(link("Giải pháp đã kiểm chứng", "/lo-trinh?tab=member&name=" + profile[1]));
    if (home) for (const item of (data.items || [])) box.append(link(item.text, item.url));
  }
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => { scheduled = false; draw(); });
  }
  new MutationObserver(schedule).observe(document.body, {childList:true, subtree:true});
  window.addEventListener("popstate", schedule);
  schedule();
})();
