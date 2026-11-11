// Autenticação por JWT: assinatura conferida, algoritmo fixo e emissor fixo.
import { jwtVerify, SignJWT } from "jose";
import { obterSegredo } from "./segredos.mjs";

const EMISSOR = "loja-api";
const ALGORITMO = "HS256";

async function chave() {
  return new TextEncoder().encode(await obterSegredo("JWT_SECRET"));
}

/** Devolve { lojaId } se o token for válido; null em qualquer outro caso. */
export async function autenticar(authorization) {
  const token = /^Bearer ([\w-]+\.[\w-]+\.[\w-]+)$/.exec(authorization ?? "")?.[1];
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, await chave(), {
      algorithms: [ALGORITMO],
      issuer: EMISSOR,
    });
    return typeof payload.lojaId === "string" ? { lojaId: payload.lojaId } : null;
  } catch {
    return null;
  }
}

/** Emite um token de 1 hora para a loja (usado pelo login e pelos testes). */
export async function emitirToken(lojaId) {
  return new SignJWT({ lojaId })
    .setProtectedHeader({ alg: ALGORITMO })
    .setIssuer(EMISSOR)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(await chave());
}
