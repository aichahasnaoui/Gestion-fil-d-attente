import traceback, os
try:
    from app import create_app
    app = create_app()
    ctx = app.app_context()
    ctx.push()
    folder = os.path.abspath(app.config['UPLOAD_FOLDER'])
    os.makedirs(folder, exist_ok=True)
    print('Upload folder:', folder)
    print('Exists:', os.path.exists(folder))
    print('Writable:', os.access(folder, os.W_OK))
    print('Files:', os.listdir(folder))
except Exception as e:
    traceback.print_exc()
