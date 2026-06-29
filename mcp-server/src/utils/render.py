import yaml
import jinja2
import sys
import os
import re

if len(sys.argv) < 4:
    print("Usage: python render.py <pillar_path> <template_path> <grains_host>", file=sys.stderr)
    sys.exit(1)

pillar_path = sys.argv[1]
template_path = sys.argv[2]
grains_host = sys.argv[3]

def load_yaml(filepath):
    with open(filepath, 'r') as f:
        return yaml.safe_load(f)

try:
    pillar_data = load_yaml(pillar_path)
except Exception as e:
    print(f"Error loading pillar: {e}", file=sys.stderr)
    sys.exit(1)

def pillar_get(key, default=None):
    parts = key.split(':')
    current = pillar_data
    for p in parts:
        if isinstance(current, dict) and p in current:
            current = current[p]
        else:
            return default
    return current

# Important: Keep trim_blocks=False and lstrip_blocks=False so Jinja doesn't collapse lines
env = jinja2.Environment(
    loader=jinja2.FileSystemLoader(os.path.dirname(template_path)),
    trim_blocks=False,
    lstrip_blocks=False
)

env.filters['dictsort'] = lambda d: sorted(d.items())
env.globals['salt'] = {'pillar.get': pillar_get}
env.globals['grains'] = {'host': grains_host, 'osrelease': '22.04'}

try:
    template = env.get_template(os.path.basename(template_path))
    rendered_config = template.render()
    
    # Remove ssl crt for sandbox testing
    rendered_config = re.sub(r'ssl crt \S+', '', rendered_config)

    # Remove errorfile for sandbox testing
    rendered_config = re.sub(r'errorfile \d+ \S+', '', rendered_config)

    # Replace AWS internal DNS with localhost for sandbox testing
    rendered_config = re.sub(r'\S+\.compute\.internal', '127.0.0.1', rendered_config)

    # Change stats socket path for sandbox testing (avoid permission denied)
    rendered_config = re.sub(r'stats socket \/var\/run\/haproxy\.stat', 'stats socket /tmp/haproxy.stat', rendered_config)

    # Process rendered config to ensure properly formatted lists
    # And handle empty lines to avoid huge gaps
    lines = rendered_config.split('\n')
    processed_lines = []
    
    for line in lines:
        if line.strip() == '':
            # Skip excessive blank lines
            if len(processed_lines) > 0 and processed_lines[-1].strip() != '':
                processed_lines.append('')
            continue
        processed_lines.append(line)
                
    print('\n'.join(processed_lines))
except Exception as e:
    print(f"Error rendering template: {e}", file=sys.stderr)
    sys.exit(1)
