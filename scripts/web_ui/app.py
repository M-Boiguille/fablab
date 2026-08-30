#!/usr/bin/env python3
"""Web UI DevOps learner — Streamlit V0."""

import json
import os

import streamlit as st
import yaml


def load_yaml(path: str):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def list_stacks():
    if not os.path.isdir("stacks"):
        return []
    return [
        d
        for d in os.listdir("stacks")
        if os.path.isdir(os.path.join("stacks", d)) and not d.startswith(".")
    ]


st.title("DevOps Learner Dashboard")

st.sidebar.header("Navigation")
stacks = list_stacks()
if not stacks:
    st.warning("Aucune stack trouvée dans ./stacks")
    st.stop()

stack = st.sidebar.selectbox("Stack", stacks)
profile = load_yaml(f"stacks/{stack}/profile.yaml")

if profile:
    current_sprint = int(profile["global"].get("current_sprint", 1))
else:
    current_sprint = 1
    st.warning("Aucun profile.yaml. Lance `scripts/learner_cli.py init`.")

sprint = st.sidebar.number_input("Sprint", min_value=1, value=current_sprint)

if profile:
    st.subheader("Vue d'ensemble")
    st.json(profile.get("global", {}))

    st.subheader("Compétences")
    skills = profile.get("skills", {})
    for skill, topics in skills.items():
        with st.expander(skill):
            rows = [
                {"topic": k, "level": v["level"], "confidence": v["confidence"]}
                for k, v in topics.items()
            ]
            if rows:
                st.bar_chart({r["topic"]: r["level"] for r in rows})
                st.table(rows)
            else:
                st.write("Aucune compétence enregistrée.")

brief_path = f"sprints/sprint_{int(sprint):02d}/brief.md"
if os.path.exists(brief_path):
    with open(brief_path, encoding="utf-8") as f:
        st.subheader("Brief du sprint")
        st.markdown(f.read())
else:
    st.info(f"Lance `start --sprint {int(sprint)}` pour générer le brief.")

book_path = f"stacks/{stack}/resources/book_toc.md"
if os.path.exists(book_path):
    with open(book_path, encoding="utf-8") as f:
        with st.expander("Ressources"):
            st.markdown(f.read())

history_path = ".chat_history.json"
if os.path.exists(history_path):
    with open(history_path, encoding="utf-8") as f:
        with st.expander("Historique de chat"):
            st.json(json.load(f))
