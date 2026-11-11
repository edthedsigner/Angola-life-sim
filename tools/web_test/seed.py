import asyncio, json, sys
sys.path.insert(0, sys.argv[1])
import websockets
async def main(user, name):
    async with websockets.connect("ws://127.0.0.1:7777") as ws:
        async def get(t):
            while True:
                m = json.loads(await ws.recv())
                if m["type"] == t: return m
        await get("welcome")
        await ws.send(json.dumps({"type": "register", "username": user, "password": "pw1234"})); print((await get("auth_response"))["success"])
        for s in range(4):
            await ws.send(json.dumps({"type": "onboarding_progress", "state": "story_in_progress", "step": s})); await get("onboarding_state")
        await ws.send(json.dumps({"type": "onboarding_progress", "state": "character_customization", "step": 3})); await get("onboarding_state")
        await ws.send(json.dumps({"type": "create_character", "name": name, "appearance": {"skin_tone": 2, "hair_style": 2, "hair_color": 1, "clothes": 1}})); print((await get("character_created"))["success"])
asyncio.run(main(sys.argv[2], sys.argv[3]))
