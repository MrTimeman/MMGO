import { mount } from "svelte";
import App from "./App.svelte";
import "./app.css";

const target = document.getElementById("app");

if (!target) {
  throw new Error("MMGO client could not find the app mount element.");
}

mount(App, { target });
