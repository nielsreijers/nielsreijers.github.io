---
layout: page
title: Contact
permalink: /contact/
navigation_weight: 4
---


<style>
.center {
  display: block;
  margin-left: auto;
  margin-right: auto;
  width: 30%;
}
</style>

<br>
<div style="text-align: center">
	<a href="#" target="_blank" data-gen-email>
		<img src="/assets/contact/email.png" width="75">
	</a>
	<br>
	<img src="/assets/contact/address.png" width="250">
</div>

<script>
	const emailAddress = atob("bWFpbHRvOm5pZWxzcmVpamVyc0BnbWFpbC5jb20");

	// Select all links with the attribute 'data-gen-email'
	const emailLinks = document.querySelectorAll('[data-gen-email]');

	emailLinks.forEach(link => {
	    link.onmouseover = link.ontouchstart = () => link.setAttribute('href', emailAddress);
	});
</script>