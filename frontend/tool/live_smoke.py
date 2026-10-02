"""Run the Flutter API client against an isolated Django server."""
import os, pathlib, subprocess, tempfile, time, urllib.request
root = pathlib.Path(__file__).resolve().parents[2]
frontend = root / 'frontend'
with tempfile.TemporaryDirectory(prefix='flowza-smoke-') as tmp:
    env = dict(os.environ, DJANGO_SECRET_KEY='integration-test-only-secret-32-characters', DEBUG='true', ALLOWED_HOSTS='localhost,127.0.0.1', DEMO_PASSWORD='integration-test-password')
    env.setdefault('DATABASE_URL', 'sqlite:///' + tmp + '/db.sqlite3')
    subprocess.run(['python', 'manage.py', 'migrate', '--noinput'], cwd=root, env=env, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['python', 'manage.py', 'seed_demo'], cwd=root, env=env, check=True)
    with open(pathlib.Path(tmp) / 'server.log', 'w') as log:
        server = subprocess.Popen(['python', 'manage.py', 'runserver', '127.0.0.1:8000', '--noreload'], cwd=root, env=env, stdout=log, stderr=log)
        try:
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError('Django exited; see server log')
                try:
                    urllib.request.urlopen('http://127.0.0.1:8000/api/schema/', timeout=1)
                    break
                except Exception:
                    time.sleep(.1)
            else:
                raise RuntimeError('Django did not become ready')
            flutter = os.environ.get('FLUTTER_BIN', 'flutter')
            subprocess.run([flutter, 'test', 'test/live_api_test.dart', '--dart-define=LIVE_API_URL=http://127.0.0.1:8000/api/v1/'], cwd=frontend, env=env, check=True)
        finally:
            server.terminate()
            server.wait(timeout=10)
