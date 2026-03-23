const express = require('express');
const fs = require('fs');
const path = require('path');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;
const ROCORE_DIR = path.join(__dirname, 'RoCore');

// Middleware
app.use(cors());
app.use(express.json());

// Get all templates metadata (without code)
app.get('/api/templates', (req, res) => {
    try {
        const files = fs.readdirSync(ROCORE_DIR).filter(f => f.endsWith('.json'));
        const templates = files.map(file => {
            const data = JSON.parse(fs.readFileSync(path.join(ROCORE_DIR, file), 'utf8'));
            return {
                id: data.id,
                name: data.name,
                keywords: data.keywords,
                scriptName: data.scriptName,
                scriptType: data.scriptType,
                parent: data.parent,
                defaults: data.defaults
            };
        });
        res.json({ success: true, templates });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

// Get specific template by ID
app.get('/api/templates/:id', (req, res) => {
    try {
        const { id } = req.params;
        const files = fs.readdirSync(ROCORE_DIR).filter(f => f.endsWith('.json'));
        
        for (const file of files) {
            const data = JSON.parse(fs.readFileSync(path.join(ROCORE_DIR, file), 'utf8'));
            if (data.id === id) {
                return res.json({ success: true, template: data });
            }
        }
        
        res.status(404).json({ success: false, error: 'Template not found' });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

// Search templates by keyword
app.get('/api/search', (req, res) => {
    try {
        const { q } = req.query;
        if (!q) {
            return res.status(400).json({ success: false, error: 'Query parameter required' });
        }
        
        const searchTerm = q.toLowerCase();
        const files = fs.readdirSync(ROCORE_DIR).filter(f => f.endsWith('.json'));
        const matches = [];
        
        for (const file of files) {
            const data = JSON.parse(fs.readFileSync(path.join(ROCORE_DIR, file), 'utf8'));
            const matchScore = calculateMatchScore(data, searchTerm);
            if (matchScore > 0) {
                matches.push({ ...data, matchScore });
            }
        }
        
        // Sort by match score (descending)
        matches.sort((a, b) => b.matchScore - a.matchScore);
        
        res.json({ success: true, templates: matches });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'ok', templatesCount: fs.readdirSync(ROCORE_DIR).filter(f => f.endsWith('.json')).length });
});

function calculateMatchScore(template, searchTerm) {
    let score = 0;
    const term = searchTerm.toLowerCase();
    const words = term.split(/\s+/);
    
    // Exact ID match
    if (template.id.toLowerCase() === term) score += 100;
    
    // ID contains term
    if (template.id.toLowerCase().includes(term)) score += 50;
    
    // ScriptName match (high priority - readable name)
    const scriptName = template.scriptName ? template.scriptName.toLowerCase() : '';
    if (scriptName === term) score += 150;
    if (scriptName.includes(term)) score += 80;
    
    // Name match (skip generic template_X names)
    const name = template.name ? template.name.toLowerCase() : '';
    if (!name.match(/^template_\d+$/)) {
        if (name.includes(term)) score += 60;
    }
    
    // Keywords match
    for (const kw of template.keywords || []) {
        const kwLower = kw.toLowerCase();
        if (kwLower === term) score += 70;
        if (kwLower.includes(term)) score += 40;
        // Check individual words
        for (const word of words) {
            if (word.length > 2 && kwLower.includes(word)) score += 25;
        }
    }
    
    return score;
}

app.listen(PORT, () => {
    console.log(`RoBot API Server running on port ${PORT}`);
    console.log(`Serving templates from: ${ROCORE_DIR}`);
});
