FROM node:20-alpine

WORKDIR /app

# Install the package
RUN npm install omni-antigravity-remote-chat --no-save

# Apply the patches to make it compatible with Antigravity
RUN cd node_modules/omni-antigravity-remote-chat/src && \
    # Patch connection.js
    sed -i "s/t.url?.includes('workbench.html') || (t.title && t.title.includes('workbench'))/t.type === 'page'/g" cdp/connection.js && \
    sed -i "s/t.url?.includes('workbench.html') && \!t.url?.includes('jetski')/t.type === 'page'/g" cdp/connection.js && \
    # Patch server.js
    sed -i "s/const CONTAINER_IDS = \['cascade', 'conversation', 'chat'\];/const CONTAINER_IDS = ['cascade', 'conversation', 'chat', 'root', 'app', '__next'];/g" server.js && \
    # We use awk here to replace the multiline block correctly in Alpine
    awk '/if \(\!cascade\) \{[ \t]*\/\/[ \t]*Debug info/ { print "if (!cascade) cascade = document.body;\n        if (!cascade) {\n            // Debug info"; next } { print }' server.js > server.js.tmp && mv server.js.tmp server.js && \
    sed -i "s/\[\.\.\.document.querySelectorAll('#conversation \[contenteditable=\"true\"\], #chat \[contenteditable=\"true\"\], #cascade \[contenteditable=\"true\"\]')\]/\[...document.querySelectorAll('body \[contenteditable=\"true\"\]')\]/g" server.js

# We expose the port that the server binds to
EXPOSE 4747

# The server connects to localhost:7800 to find the CDP endpoint.
# When run with network_mode: host, this will connect to the host machine.
CMD ["node", "node_modules/omni-antigravity-remote-chat/src/server.js"]
