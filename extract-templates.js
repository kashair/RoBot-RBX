const fs = require('fs');
const path = require('path');

const luaFile = fs.readFileSync('/home/mord/Documents/RoBot-Dev/RoBot/RoBot.lua', 'utf8');

// Extract all T() calls - this is a simplified parser
const templates = [];
const lines = luaFile.split('\n');

let currentTemplate = null;
let braceDepth = 0;
let inCodeBlock = false;
let codeContent = [];
let collecting = false;
let startLine = 0;

for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    
    if (trimmed.startsWith('T(') && !collecting) {
        collecting = true;
        startLine = i;
        currentTemplate = { raw: [] };
        braceDepth = 1;
        continue;
    }
    
    if (collecting) {
        currentTemplate.raw.push(line);
        
        // Check for code block start
        if (trimmed.startsWith('[[')) {
            inCodeBlock = true;
            codeContent = [line];
            continue;
        }
        
        // Check for code block end
        if (inCodeBlock && trimmed.endsWith(']]') && !trimmed.startsWith('[[')) {
            inCodeBlock = false;
            codeContent.push(line);
            currentTemplate.code = codeContent.join('\n');
            continue;
        }
        
        if (inCodeBlock) {
            codeContent.push(line);
            continue;
        }
        
        // Track braces
        for (const char of line) {
            if (char === '(' || char === '{' || char === '[') braceDepth++;
            if (char === ')' || char === '}' || char === ']') braceDepth--;
        }
        
        // Check for template end - line with just ), or ),
        if (!inCodeBlock && /^\s*\),?\s*$/.test(line)) {
            templates.push(currentTemplate);
            collecting = false;
            currentTemplate = null;
            continue;
        }
    }
}

console.log(`Found ${templates.length} templates`);

// Parse each template to extract structured data
templates.forEach((t, idx) => {
    const rawText = t.raw.join('\n');
    
    // Extract id - first string after T(
    const idMatch = rawText.match(/T\(\s*["']([^"']+)["']/);
    const id = idMatch ? idMatch[1] : `template_${idx}`;
    
    // Extract name - second string
    const nameMatch = rawText.match(/T\([^,]+,\s*["']([^"']+)["']/);
    const name = nameMatch ? nameMatch[1] : id;
    
    // Extract keywords array
    const keywordsMatch = rawText.match(/\{\s*([^}]+)\s*\}/);
    let keywords = [];
    if (keywordsMatch) {
        keywords = keywordsMatch[1].split(',').map(k => k.trim().replace(/["']/g, '')).filter(k => k);
    }
    
    // Extract scriptName
    const scriptNameMatch = rawText.match(/["'](RoBot_[^"']+)["']/);
    const scriptName = scriptNameMatch ? scriptNameMatch[1] : `RoBot_${id}`;
    
    // Extract scriptType and parent
    const typeMatch = rawText.match(/"(Script|LocalScript|ModuleScript)"/);
    const scriptType = typeMatch ? typeMatch[1] : 'Script';
    
    // Extract defaults if present
    const defaultsMatch = rawText.match(/\{\s*([A-Z_]+\s*=\s*["'][^"']*["']\s*,?\s*)+\}/);
    let defaults = {};
    if (defaultsMatch) {
        const defaultsText = defaultsMatch[0];
        const keyValueMatches = defaultsText.matchAll(/([A-Z_]+)\s*=\s*["']([^"']*)["']/g);
        for (const match of keyValueMatches) {
            defaults[match[1]] = match[2];
        }
    }
    
    // Extract parent
    const parentMatch = rawText.match(/"(ServerScriptService|ReplicatedStorage|StarterGui|StarterPlayer|Workspace)"/g);
    const parent = parentMatch && parentMatch.length > 1 ? parentMatch[parentMatch.length - 1].replace(/"/g, '') : 'ServerScriptService';
    
    // Clean up code - extract just the code from [[...]]
    let code = t.code || '';
    if (code.startsWith('[[')) {
        code = code.slice(2);
    }
    if (code.endsWith(']]')) {
        code = code.slice(0, -2);
    }
    
    const templateData = {
        id,
        name,
        keywords,
        scriptName,
        scriptType,
        parent,
        defaults,
        code
    };
    
    const outputPath = path.join('/home/mord/Documents/RoBot-Dev/RoCore', `${scriptName}.json`);
    fs.writeFileSync(outputPath, JSON.stringify(templateData, null, 2));
    console.log(`Created: ${scriptName}.json`);
});

console.log('Done!');
