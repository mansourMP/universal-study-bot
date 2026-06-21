import os

root_dir = 'lib'
replacements = {
    'DragonColors': 'AppColors',
    'DragonButton': 'GameButton', 
}

for subdir, dirs, files in os.walk(root_dir):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(subdir, file)
            with open(filepath, 'r') as f:
                content = f.read()
            
            new_content = content
            for old, new in replacements.items():
                new_content = new_content.replace(old, new)
            
            if new_content != content:
                print(f"Updating {filepath}")
                with open(filepath, 'w') as f:
                    f.write(new_content)
