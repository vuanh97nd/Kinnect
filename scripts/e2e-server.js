import { createApp } from "../server.js";
const { server } = createApp({authLimit:200});
server.listen(Number(process.env.E2E_PORT || 3210), "127.0.0.1");
