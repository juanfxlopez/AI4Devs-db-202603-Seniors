import path from 'path';
import dotenv from 'dotenv';

const result = dotenv.config({ path: path.resolve(__dirname, '../../../.env') });

if (result.parsed) {
    Object.keys(result.parsed).forEach((key) => {
        process.env[key] = expandEnvValue(process.env[key] || result.parsed![key]);
    });
}

function expandEnvValue(value: string): string {
    return value.replace(/\$\{([A-Z0-9_]+)\}/gi, (_match, name: string) => process.env[name] || '');
}
